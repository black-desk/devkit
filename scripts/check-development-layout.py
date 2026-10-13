#!/usr/bin/env python3
"""Check installed channel development interfaces and runtime search paths."""

from pathlib import Path
import re
import subprocess
import sys

prefix = Path(sys.argv[1]).resolve()
errors = []
for directory in ["include", "lib/pkgconfig", "lib/cmake", "share/cmake"]:
    root = prefix / directory
    if root.exists():
        for path in root.rglob("*"):
            if path.is_file() or path.is_symlink():
                errors.append(f"public development interface: {path}")
for path in (prefix / "lib").glob("lib*"):
    if path.name.endswith(".a") or (path.name.endswith(".so") and path.is_symlink()):
        errors.append(f"public link-time interface: {path}")

for path in prefix.rglob("*"):
    if path.is_symlink() or not path.is_file():
        continue
    with path.open("rb") as stream:
        if stream.read(4) != b"\x7fELF":
            continue
    dynamic = subprocess.run(
        ["readelf", "-d", str(path)], check=True, capture_output=True, text=True
    ).stdout
    match = re.search(r"\((?:RUNPATH|RPATH)\).*?\[(.*?)\]", dynamic)
    if match:
        for entry in match[1].split(":"):
            if entry.startswith("/") or "devkit/lib" in entry:
                errors.append(f"non-runtime search path in {path}: {entry}")
if errors:
    raise SystemExit("\n".join(errors))
print("hidden development interfaces and runtime search paths: OK")
