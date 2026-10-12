#!/usr/bin/env python3
"""Reject ELF files requiring a newer glibc than the channel sysroot."""

import re
import subprocess
import sys
from pathlib import Path


def main():
    prefix = Path(sys.argv[1]).resolve()
    failures = []
    count = 0
    for path in sorted(prefix.rglob("*")):
        if path.is_symlink() or not path.is_file():
            continue
        with path.open("rb") as stream:
            if stream.read(4) != b"\x7fELF":
                continue
        count += 1
        result = subprocess.run(
            ["readelf", "--version-info", str(path)],
            check=True,
            capture_output=True,
            text=True,
        )
        versions = set(re.findall(r"GLIBC_(\d+\.\d+(?:\.\d+)?)", result.stdout))
        too_new = sorted(
            version
            for version in versions
            if tuple(map(int, version.split("."))) > (2, 28, 0)
        )
        if too_new:
            failures.append(f"{path.relative_to(prefix)}: {', '.join(too_new)}")
    if failures:
        raise SystemExit("glibc baseline exceeded:\n" + "\n".join(failures))
    print(f"glibc <= 2.28 baseline: OK ({count} ELF files)")


if __name__ == "__main__":
    main()
