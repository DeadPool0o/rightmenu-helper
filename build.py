#!/usr/bin/env python3
"""Build a local macOS app and its Finder Sync extension using Command Line Tools."""
import argparse
import os
import pathlib
import plistlib
import shutil
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument("--identity", default="-", help="codesign identity; default is local ad-hoc signing")
parser.add_argument("--universal", action="store_true", help="also compile x86_64")
args = parser.parse_args()
build = ROOT / "build"
build.mkdir(exist_ok=True)
cache = build / "ModuleCache"
cache.mkdir(exist_ok=True)
app = build / "Applications.noindex/右键助手.app"
if app.exists():
    shutil.rmtree(app)
ext = app / "Contents/PlugIns/RightClickFinder.appex"
for bundle in (app, ext):
    (bundle / "Contents/MacOS").mkdir(parents=True, exist_ok=True)
    (bundle / "Contents/Resources").mkdir(exist_ok=True)

def plist(path, value):
    path.write_bytes(plistlib.dumps(value, sort_keys=False))

base = {"CFBundleInfoDictionaryVersion": "6.0", "CFBundleVersion": "16", "CFBundleShortVersionString": "0.2.11",
        "LSMinimumSystemVersion": "13.0", "CFBundleSupportedPlatforms": ["MacOSX"], "LSUIElement": True}
services = [{"NSMenuItem": {"default": "用 ChatGPT 打开（右键助手）"}, "NSMessage": "openInChatGPT",
             "NSPortName": "RightClickAssistant", "NSSendTypes": ["NSFilenamesPboardType", "public.file-url"],
             "NSSendFileTypes": ["public.item"], "NSRequiredContext": {"NSServiceCategory": "public.item"}}]
for title, message, user_data in [("百度翻译（右键助手）", "translateText", "baidu"),
                                  ("谷歌翻译（右键助手）", "translateText", "google"),
                                  ("生成二维码（右键助手）", "generateQRCode", "")]:
    services.append({"NSMenuItem": {"default": title}, "NSMessage": message, "NSUserData": user_data,
                     "NSPortName": "RightClickAssistant", "NSSendTypes": ["public.utf8-plain-text", "NSStringPboardType"],
                     "NSRequiredContext": {"NSServiceCategory": "Text"}})
plist(app / "Contents/Info.plist", {**base, "CFBundleName": "RightClickAssistant", "CFBundleDisplayName": "右键助手",
      "CFBundleIdentifier": "local.kingdee.RightClickAssistant", "CFBundleExecutable": "RightClickAssistant",
      "CFBundlePackageType": "APPL", "CFBundleIconFile": "AppIcon.icns", "NSPrincipalClass": "NSApplication", "NSServices": services,
      "CFBundleURLTypes": [{"CFBundleURLName": "RightClickAssistant", "CFBundleURLSchemes": ["rightclick-assistant"]}]})
plist(ext / "Contents/Info.plist", {**base, "CFBundleName": "RightClickFinder", "CFBundleDisplayName": "右键助手",
      "CFBundleIdentifier": "local.kingdee.RightClickAssistant.Finder", "CFBundleExecutable": "RightClickFinder",
      "CFBundlePackageType": "XPC!", "NSExtension": {"NSExtensionPointIdentifier": "com.apple.FinderSync",
      "NSExtensionPrincipalClass": "RightClickFinderSync", "NSExtensionAttributes": {}}})
entitlements = build / "extension.entitlements"
plist(entitlements, {"com.apple.security.app-sandbox": True, "com.apple.security.files.user-selected.read-write": True,
    "com.apple.security.temporary-exception.shared-preference.read-only": ["local.kingdee.RightClickAssistant.preferences"]})

common = sorted((ROOT / "Sources/Shared").glob("*.swift"))
architectures = ["arm64", "x86_64"] if args.universal else [os.uname().machine]
env = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(cache), SWIFT_MODULECACHE_PATH=str(cache))
def run(command):
    print("Running:", " ".join(map(str, command)), flush=True)
    subprocess.run(list(map(str, command)), check=True, cwd=ROOT, env=env)

for name, bundle, sources, frameworks, flags in [
    ("RightClickAssistant", app, [*common, *sorted((ROOT / "Sources/App").glob("*.swift"))],
     ["AppKit", "FinderSync", "ServiceManagement", "CoreImage", "ImageIO", "UniformTypeIdentifiers"], []),
    ("RightClickFinder", ext, [*common, ROOT / "Sources/Extension/FinderSync.swift"], ["AppKit", "FinderSync", "UniformTypeIdentifiers"],
     ["-application-extension", "-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"]),
]:
    binaries = []
    for arch in architectures:
        out = build / (name + "-" + arch)
        command = ["/usr/bin/xcrun", "swiftc", "-swift-version", "5", "-O", "-parse-as-library",
                   "-target", arch + "-apple-macosx13.0", "-module-name", name, "-module-cache-path", cache]
        for framework in frameworks:
            command += ["-framework", framework]
        run([*command, *flags, *sources, "-o", out]); binaries.append(out)
    destination = bundle / "Contents/MacOS" / name
    if len(binaries) == 1:
        shutil.copy2(binaries[0], destination)
    else:
        run(["/usr/bin/lipo", "-create", *binaries, "-output", destination])

shutil.copy2(ROOT / "Resources/AppIcon.icns", app / "Contents/Resources/AppIcon.icns")
shutil.copytree(ROOT / "Resources/Templates", app / "Contents/Resources/Templates")
run(["/usr/bin/codesign", "--force", "--sign", args.identity, "--timestamp=none", "--options", "runtime",
     "--entitlements", entitlements, ext])
run(["/usr/bin/codesign", "--force", "--sign", args.identity, "--timestamp=none", "--options", "runtime", app])
run(["/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=2", app])
print("Built:", app, flush=True)
