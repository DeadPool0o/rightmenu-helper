#!/usr/bin/env python3
"""Build and verify a universal macOS Installer package and portable app ZIP."""
import argparse
import datetime
import hashlib
import json
import pathlib
import plistlib
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parent
APP = ROOT / "build/Applications.noindex/右键助手.app"
PACKAGE_ID = "local.kingdee.RightClickAssistant.pkg"


def run(*command, capture=False):
    command = list(map(str, command))
    print("Running:", " ".join(command), flush=True)
    result = subprocess.run(command, cwd=ROOT, check=True, text=True,
                            stdout=subprocess.PIPE if capture else None)
    return result.stdout.strip() if capture else None


def verify_app(app):
    run("/usr/bin/codesign", "--verify", "--deep", "--strict", app)
    for relative in ("Contents/MacOS/RightClickAssistant",
                     "Contents/PlugIns/RightClickFinder.appex/Contents/MacOS/RightClickFinder"):
        binary = app / relative
        architectures = set(run("/usr/bin/lipo", "-archs", binary, capture=True).split())
        if architectures != {"arm64", "x86_64"}:
            raise RuntimeError(f"{binary.name} must contain arm64 and x86_64; found {architectures}")
        if binary.read_bytes() != (APP / relative).read_bytes():
            raise RuntimeError(f"Packaged executable differs from build: {relative}")
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    for bundle in (app, app / "Contents/PlugIns/RightClickFinder.appex"):
        bundle_info = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
        if bundle_info.get("CFBundleDevelopmentRegion") != "zh-Hans" or "zh-Hans" not in bundle_info.get("CFBundleLocalizations", []):
            raise RuntimeError(f"Simplified Chinese localization is missing: {bundle.name}")
    if not (app / "Contents/Resources" / info["CFBundleIconFile"]).is_file():
        raise RuntimeError("Application icon is missing")
    for name in ("Word.docx", "Excel.xlsx", "PowerPoint.pptx"):
        if not (app / "Contents/Resources/Templates" / name).is_file():
            raise RuntimeError(f"Built-in template is missing: {name}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skip-build", action="store_true", help="package an existing universal build")
    parser.add_argument("--expected-version", help="reject a build that does not match the release tag")
    args = parser.parse_args()
    if not args.skip_build:
        run(sys.executable, ROOT / "build.py", "--universal")
    verify_app(APP)
    info = plistlib.loads((APP / "Contents/Info.plist").read_bytes())
    version = info["CFBundleShortVersionString"]
    if args.expected_version and args.expected_version != version:
        raise RuntimeError(f"Release tag is {args.expected_version}, but application version is {version}")
    with tempfile.TemporaryDirectory(prefix="installer-", suffix=".noindex", dir=ROOT / "build") as temporary:
        create_packages(info, pathlib.Path(temporary))


def create_packages(info, work):
    version = info["CFBundleShortVersionString"]
    minimum = info["LSMinimumSystemVersion"]
    stage = work / "root"
    resources = work / "resources"
    stage.mkdir(parents=True)
    resources.mkdir()
    run("/usr/bin/ditto", "--noqtn", APP, stage / APP.name)
    components = work / "components.plist"
    run("/usr/bin/pkgbuild", "--analyze", "--root", stage, components)
    definitions = plistlib.loads(components.read_bytes())

    def configure(bundles):
        for bundle in bundles:
            bundle.update(BundleIsRelocatable=False, BundleIsVersionChecked=True,
                          BundleHasStrictIdentifier=True, BundleOverwriteAction="upgrade")
            configure(bundle.get("ChildBundles", []))

    configure(definitions)
    components.write_bytes(plistlib.dumps(definitions))
    component = work / "RightClickAssistant.pkg"
    run("/usr/bin/pkgbuild", "--root", stage, "--component-plist", components,
        "--identifier", PACKAGE_ID, "--version", version, "--install-location", "/Applications",
        "--ownership", "recommended", "--scripts", ROOT / "Packaging/Scripts", component)

    for source in (ROOT / "Packaging/Resources").glob("*.html"):
        resources.joinpath(source.name).write_text(
            source.read_text().replace("@VERSION@", version).replace("@MINIMUM_OS@", minimum))
    distribution = work / "Distribution.xml"
    distribution.write_text((ROOT / "Packaging/Distribution.xml").read_text()
                            .replace("@INSTALLATION_SCRIPT@", (ROOT / "Packaging/CheckInstallation.js").read_text())
                            .replace("@VERSION@", version).replace("@BUILD_NUMBER@", info["CFBundleVersion"])
                            .replace("@MINIMUM_OS@", minimum))
    output = ROOT / "dist"
    output.mkdir(exist_ok=True)
    stem = f"RightClickAssistant-{version}-macos-universal"
    installer = output / (stem + ".pkg")
    archive = output / (stem + ".zip")
    for artifact in (installer, archive):
        artifact.unlink(missing_ok=True)
    run("/usr/bin/productbuild", "--distribution", distribution, "--resources", resources,
        "--package-path", work, "--identifier", info["CFBundleIdentifier"],
        "--version", version, installer)
    run("/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", APP, archive)

    # Inspect the actual distributables, including their extracted app signatures.
    expanded = work / "expanded"
    run("/usr/sbin/pkgutil", "--expand-full", installer, expanded)
    package_info = ET.parse(expanded / "RightClickAssistant.pkg/PackageInfo").getroot()
    if package_info.attrib["install-location"] != "/Applications":
        raise RuntimeError("Installer destination must be /Applications")
    if package_info.attrib["identifier"] != PACKAGE_ID or package_info.attrib["version"] != version:
        raise RuntimeError("Installer identity or version does not match the application")
    postinstall = expanded / "RightClickAssistant.pkg/Scripts/postinstall"
    if postinstall.read_bytes() != (ROOT / "Packaging/Scripts/postinstall").read_bytes():
        raise RuntimeError("Installer is missing the setup launcher")
    payload = expanded / "RightClickAssistant.pkg/Payload" / APP.name
    verify_app(payload)
    zipped = work / "zip-expanded"
    run("/usr/bin/ditto", "-x", "-k", archive, zipped)
    verify_app(zipped / APP.name)

    commit = subprocess.run(["git", "rev-parse", "--verify", "HEAD"], cwd=ROOT,
                            capture_output=True, text=True)
    source_status = subprocess.run(["git", "status", "--porcelain"], cwd=ROOT,
                                   capture_output=True, text=True, check=True)
    metadata = output / "release-info.json"
    metadata.write_text(json.dumps({
        "name": "右键助手", "version": version, "build": info["CFBundleVersion"],
        "bundle_identifier": info["CFBundleIdentifier"], "package_identifier": PACKAGE_ID,
        "minimum_macos": minimum, "architectures": ["arm64", "x86_64"],
        "install_location": "/Applications/右键助手.app",
        "application_signing": "ad-hoc", "installer_signed": False, "notarized": False,
        "opens_app_after_install": True,
        "upgrade_behavior": "replace-in-place; allow-repair; block-downgrade; preserve-user-data",
        "source_commit": commit.stdout.strip() if commit.returncode == 0 else None,
        "source_dirty": bool(source_status.stdout.strip()),
        "built_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "assets": [{"name": item.name, "bytes": item.stat().st_size} for item in (installer, archive)],
    }, ensure_ascii=False, indent=2) + "\n")
    checksums = output / "SHA256SUMS.txt"
    checksums.write_text("".join(f"{hashlib.sha256(item.read_bytes()).hexdigest()}  {item.name}\n"
                                for item in (installer, archive, metadata)))
    print(f"Verified installer and ZIP: {output}")


if __name__ == "__main__":
    main()
