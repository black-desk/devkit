#!/usr/bin/env python3
"""Set relocatable RUNPATH on newly installed ELF files, preserving host inputs."""

import json
import os
from pathlib import Path
import stat
import struct
import subprocess
import sys

prefix = Path(sys.argv[1]).resolve()
dependencies = set()
for record in (prefix / "conda-meta").glob("*.json"):
    dependencies.update(json.loads(record.read_text()).get("files", []))

for path in sorted(prefix.rglob("*")):
    if path.is_symlink() or not path.is_file():
        continue
    if path.relative_to(prefix).as_posix() in dependencies:
        continue
    with path.open("rb") as stream:
        header = stream.read(64)
        if header[:4] != b"\x7fELF":
            continue
        if header[4:6] != b"\x02\x01":
            raise RuntimeError(f"unsupported ELF class or endianness: {path}")
        offset = struct.unpack_from("<Q", header, 32)[0]
        size, count = struct.unpack_from("<HH", header, 54)
        dynamic = False
        for index in range(count):
            stream.seek(offset + index * size)
            dynamic |= struct.unpack("<I", stream.read(4))[0] == 2
        if not dynamic:
            continue
    relative = os.path.relpath(prefix / "lib/devkit/lib", path.parent)
    runpath = "$ORIGIN" if relative == "." else f"$ORIGIN:$ORIGIN/{relative}"
    mode = stat.S_IMODE(path.stat().st_mode)
    try:
        path.chmod(mode | stat.S_IWUSR)
        subprocess.run(["patchelf", "--set-rpath", runpath, str(path)], check=True)
    finally:
        path.chmod(mode)
