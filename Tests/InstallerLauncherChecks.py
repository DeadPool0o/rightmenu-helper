"""Exercise the real postinstall shell script with isolated OS-command stubs."""
import os
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(suffix=".noindex") as temporary:
    work = pathlib.Path(temporary)
    app = work / "Installed.app"
    app.mkdir()
    log = work / "launch.log"
    commands = {
        "/usr/bin/stat": 'printf "%s" "$RCA_TEST_USER"',
        "/usr/bin/id": 'printf "%s" "$RCA_TEST_UID"',
        "/bin/launchctl": 'printf "%s\\n" "$@" > "$RCA_TEST_LOG"; exit "${RCA_TEST_LAUNCH_STATUS:-0}"',
    }
    source = (ROOT / "Packaging/Scripts/postinstall").read_text()
    for original, body in commands.items():
        stub = work / pathlib.Path(original).name
        stub.write_text("#!/bin/sh\n" + body + "\n")
        stub.chmod(0o755)
        source = source.replace(original, str(stub))
    source = source.replace("app='/Applications/右键助手.app'", "app='" + str(app) + "'")
    script = work / "postinstall"
    script.write_text(source)
    cases = [
        ("logged-in user", "alice", "501", "/", True, "0"),
        ("no user", "", "501", "/", False, "0"),
        ("root", "root", "0", "/", False, "0"),
        ("login window", "loginwindow", "0", "/", False, "0"),
        ("setup assistant", "_mbsetupuser", "248", "/", False, "0"),
        ("system account", "daemon", "500", "/", False, "0"),
        ("invalid uid", "alice", "invalid", "/", False, "0"),
        ("other system volume", "alice", "501", "/Volumes/Other", False, "0"),
        ("launch failure does not fail install", "alice", "501", "/", True, "1"),
    ]
    for name, user, uid, volume, launches, status in cases:
        log.unlink(missing_ok=True)
        env = dict(os.environ, RCA_TEST_USER=user, RCA_TEST_UID=uid,
                   RCA_TEST_LOG=str(log), RCA_TEST_LAUNCH_STATUS=status)
        subprocess.run(["/bin/sh", str(script), "package", "/Applications", volume],
                       env=env, check=True, capture_output=True, text=True)
        assert log.exists() == launches, name
        if launches:
            assert log.read_text().splitlines() == [
                "asuser", uid, "/usr/bin/sudo", "-H", "-u", user, "--", "/usr/bin/open", str(app)], name
    print(f"Installer launch-session checks passed: {len(cases)}")
