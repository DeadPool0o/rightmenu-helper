#!/usr/bin/env python3
import pathlib
import shutil
import struct
import subprocess
import zipfile
ROOT = pathlib.Path(__file__).resolve().parent
build = ROOT / "build"
build.mkdir(exist_ok=True)
fixtures = build / "check-fixtures"
if fixtures.exists():
    shutil.rmtree(fixtures)
fixtures.mkdir()
for name, entry in [("safe", "nested/safe.txt"), ("traversal", "../escape.txt")]:
    with zipfile.ZipFile(fixtures / (name + ".zip"), "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr(entry, "safe content")
with zipfile.ZipFile(fixtures / "symlink.zip", "w") as z:
    info = zipfile.ZipInfo("link")
    info.create_system = 3
    info.external_attr = 0o120777 << 16
    z.writestr(info, "../escape")
with zipfile.ZipFile(fixtures / "local-mismatch.zip", "w") as z:
    z.writestr("safe.txt", "safe")
p = fixtures / "local-mismatch.zip"
b = bytearray(p.read_bytes()); b[30:38] = b"evil.txt"; p.write_bytes(b)
b = bytearray((fixtures / "safe.zip").read_bytes()); end = b.rfind(b"PK\x05\x06")
struct.pack_into("<I", b, end+16, 0xFFFFFF00)
(fixtures / "invalid-offset.zip").write_bytes(b)
command = ["/usr/bin/xcrun", "swiftc", "-swift-version", "5", "-parse-as-library", "-module-cache-path", str(build / "ModuleCache"),
           "-framework", "AppKit", "-framework", "CoreImage", "-framework", "ImageIO", "-framework", "UniformTypeIdentifiers",
           str(ROOT / "Sources/Shared/Core.swift"), str(ROOT / "Sources/App/Media.swift"), str(ROOT / "Tests/Checks.swift"),
           "-o", str(build / "checks")]
subprocess.run(command, check=True)
subprocess.run([str(build / "checks"), str(fixtures)], check=True)
for name in ["Word.docx", "Excel.xlsx", "PowerPoint.pptx"]:
    with zipfile.ZipFile(ROOT / "Resources/Templates" / name) as z:
        assert z.testzip() is None
        assert "[Content_Types].xml" in z.namelist()
        assert "_rels/.rels" in z.namelist()
print("Office template ZIP structures validated.")
