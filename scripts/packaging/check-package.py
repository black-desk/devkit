#!/usr/bin/env python3
"""Audit package-owned files, or a completed channel's installed prefix."""

import argparse
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys

PUBLIC_DEVELOPMENT = ("include", "lib/pkgconfig", "lib/cmake", "share/cmake")
TEST_INPUTS = PurePosixPath("etc/conda/test-files")
DEVELOPMENT = PurePosixPath("lib/devkit")
PRIVATE_LIB = DEVELOPMENT / "lib"
# These are unmodified target-system inputs, not channel-built runtime files.
SYSROOTS = tuple(
    PurePosixPath(triplet) / "sysroot"
    for triplet in ("x86_64-pc-linux-gnu", "x86_64-conda-linux-gnu")
)


def package_files(prefix, package):
    """Use installation ownership records, never audit dependencies as this package."""
    records = []
    for record in (prefix / "conda-meta").glob("*.json"):
        data = json.loads(record.read_text())
        if data.get("name") == package:
            records.append(data)
    if len(records) != 1:
        raise ValueError(
            f"expected one installed record for {package}, got {len(records)}"
        )
    if "files" not in records[0]:
        raise ValueError(f"missing file ownership list for {package}")
    return records[0]["files"]


def runpath_errors(path, prefix, dynamic):
    errors = []
    if re.search(r"\(RPATH\)", dynamic):
        errors.append(f"DT_RPATH is forbidden; use DT_RUNPATH: {path}")
    for match in re.finditer(r"\((?:RUNPATH|RPATH)\).*?\[(.*?)\]", dynamic):
        for entry in match[1].split(":"):
            if entry == "$ORIGIN" or entry == "${ORIGIN}":
                suffix = ""
            elif entry.startswith("$ORIGIN/"):
                suffix = entry[len("$ORIGIN/") :]
            elif entry.startswith("${ORIGIN}/"):
                suffix = entry[len("${ORIGIN}/") :]
            else:
                errors.append(f"non-runtime search path in {path}: {entry!r}")
                continue
            if "$" in suffix:
                errors.append(f"unsupported runtime path token in {path}: {entry!r}")
                continue
            # Normalize parent traversal and resolve installed directory aliases.
            target = (path.parent / suffix).resolve()
            if not target.is_relative_to(prefix):
                errors.append(f"runtime search path escapes prefix in {path}: {entry}")
            elif target.is_relative_to(prefix / str(DEVELOPMENT)) and not (
                target.is_relative_to(prefix / str(PRIVATE_LIB))
                or target.is_relative_to(prefix / "lib/devkit/libexec")
                or target.is_relative_to(prefix / "lib/devkit/sbin")
            ):
                errors.append(f"metadata runtime search path in {path}: {entry}")
    return errors


def check_prefix(
    prefix, files=None, *, check_runpath=True, allow_seed_runtime_aliases=False
):
    prefix = prefix.resolve()
    if files is None:
        files = [
            path.relative_to(prefix).as_posix()
            for path in prefix.rglob("*")
            if path.is_symlink() or path.is_file()
        ]
    errors = []
    for name in sorted(set(files)):
        relative = PurePosixPath(name)
        if relative.is_absolute() or ".." in relative.parts:
            errors.append(f"invalid package file path: {name}")
            continue
        if not relative.parts:
            errors.append(f"invalid package file path: {name!r}")
            continue
        if any(relative.is_relative_to(root) for root in SYSROOTS):
            continue
        if relative.is_relative_to(TEST_INPUTS) or relative.parts[0] in (
            "info",
            "conda-meta",
        ):
            continue
        path = prefix / name
        if any(relative.is_relative_to(root) for root in PUBLIC_DEVELOPMENT):
            errors.append(f"public development interface: {path}")
        if relative.parent == PurePosixPath("lib") and relative.name.startswith("lib"):
            if relative.suffix == ".a" or (
                relative.suffix == ".so" and path.is_symlink()
            ):
                errors.append(f"public link-time interface: {path}")
        if relative.parent == PurePosixPath("lib") and ".so." in relative.name:
            compatible_alias = (
                allow_seed_runtime_aliases
                and path.is_symlink()
                and path.resolve().is_relative_to(prefix / str(PRIVATE_LIB))
            )
            if not compatible_alias:
                errors.append(f"public runtime library: {path}")
        if path.is_symlink():
            if relative.is_relative_to(DEVELOPMENT):
                link = os.readlink(path)
                if os.path.isabs(link) or not path.resolve().is_relative_to(prefix):
                    errors.append(f"non-relocatable development link: {path} -> {link}")
                elif not path.exists():
                    # Installed tests have dependencies available, unlike isolated archives.
                    errors.append(f"broken development link: {path} -> {link}")
            continue
        if not path.is_file():
            errors.append(f"missing package file: {path}")
            continue
        with path.open("rb") as stream:
            if stream.read(4) != b"\x7fELF":
                continue
        dynamic = subprocess.run(
            ["readelf", "-d", str(path)],
            check=True,
            capture_output=True,
            text=True,
            env={**os.environ, "LC_ALL": "C"},
        ).stdout
        if check_runpath:
            errors.extend(runpath_errors(path, prefix, dynamic))
        if (
            relative.is_relative_to(DEVELOPMENT)
            and any(
                relative.is_relative_to(DEVELOPMENT / directory)
                for directory in (
                    "include",
                    "lib/pkgconfig",
                    "lib/cmake",
                    "share/cmake",
                )
            )
            and "Dynamic section at" in dynamic
        ):
            errors.append(f"runtime ELF in metadata directory: {path}")
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("prefix", type=Path)
    parser.add_argument("--package", help="audit only this installed package's files")
    parser.add_argument(
        "--skip-runpath-check",
        action="store_true",
        help="preserve upstream RPATH/RUNPATH for imported binaries; still check layout",
    )
    parser.add_argument(
        "--allow-seed-runtime-aliases",
        action="store_true",
        help="allow dirty-only public SONAME aliases to private libraries",
    )
    args = parser.parse_args()
    try:
        files = package_files(args.prefix, args.package) if args.package else None
        errors = check_prefix(
            args.prefix,
            files,
            check_runpath=not args.skip_runpath_check,
            allow_seed_runtime_aliases=args.allow_seed_runtime_aliases,
        )
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        parser.exit(1, f"package audit failed: {exc}\n")
    if errors:
        parser.exit(1, "\n".join(errors) + "\n")
    checks = (
        "package layout"
        if args.skip_runpath_check
        else "package layout and ELF RUNPATH"
    )
    print(f"{checks}: OK ({args.package or 'completed prefix'})")


if __name__ == "__main__":
    main()
