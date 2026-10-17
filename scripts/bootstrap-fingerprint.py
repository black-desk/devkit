#!/usr/bin/env python3
"""Hash bootstrap inputs independently of the commit and ordinary recipes."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import stat
import subprocess

ROOT = Path(__file__).resolve().parent.parent
# Bump when cache semantics or non-file inputs change. The workflow pins the
# runner image label, Pixi version and action/tool revisions hashed below.
DOMAIN = b"devkit-bootstrap-v1-linux-64-selfhost-upstream-tests\0"
REQUIRED = (
    "bootstrap-order.json",
    "seed-packages.tsv",
    "pixi.toml",
    "pixi.lock",
)
SHARED = (
    "scripts",
    "variants",
    ".github/workflows/packages.yml",
    ".gitignore",
    ".gitmodules",
    "retired-packages.json",
)


def fingerprint(root=ROOT):
    root = root.resolve()
    order = json.loads((root / "bootstrap-order.json").read_text())
    if (
        not isinstance(order, list)
        or not order
        or any(
            not isinstance(name, str) or not name or "/" in name or name in (".", "..")
            for name in order
        )
    ):
        raise ValueError("invalid bootstrap order")
    scopes = {root / name for name in (*REQUIRED, *SHARED)}
    for name in REQUIRED:
        if not (root / name).is_file():
            raise ValueError(f"missing bootstrap input: {name}")
    local_files = set()
    for name in order:
        directory = root / "recipes" / name
        scopes.add(directory)
        recipe = directory / "recipe.yaml"
        # All current local sources are literal paths. Fail rather than silently
        # omit a future templated/multiline path; extend this reader if needed.
        for line in recipe.read_text().splitlines():
            if line.lstrip().startswith("#") or not re.search(r"\bpath\s*:", line):
                continue
            match = re.fullmatch(r"\s*(?:-\s*)?path:\s*(.*?)\s*", line)
            if match is None:
                raise ValueError(f"unsupported local source syntax in {recipe}")
            values = shlex.split(match[1], comments=True)
            if len(values) != 1 or any(c in values[0] for c in "$*{}>|\n"):
                raise ValueError(f"unsupported local source path in {recipe}")
            source = (directory / values[0]).resolve()
            if not source.is_relative_to(root) or not source.exists():
                raise ValueError(
                    f"local source is missing or outside repository: {source}"
                )
            scopes.add(source)
            if source.is_file():
                local_files.add(source.relative_to(root).as_posix())

    # Match the planner's working-tree behavior, including new non-ignored
    # inputs. Generated output/cache trees are excluded by Git's ignore rules.
    names = (
        subprocess.check_output(
            [
                "git",
                "-C",
                str(root),
                "ls-files",
                "--cached",
                "--others",
                "--exclude-standard",
                "-z",
            ]
        )
        .decode()
        .split("\0")
    )
    selected = set(REQUIRED) | local_files
    for name in filter(None, names):
        path = root / name
        if any(path == scope or path.is_relative_to(scope) for scope in scopes):
            selected.add(name)
    checksum = hashlib.sha256(DOMAIN)
    for name in sorted(selected):
        path = root / name
        mode = path.lstat().st_mode
        if path.is_symlink():
            # External symlink targets could change without changing the key.
            raise ValueError(f"symlink bootstrap input needs explicit handling: {name}")
        if not stat.S_ISREG(mode):
            raise ValueError(
                f"non-file bootstrap input needs explicit handling: {name}"
            )
        data = path.read_bytes()
        descriptor = json.dumps(
            [name, bool(mode & stat.S_IXUSR), len(data)], separators=(",", ":")
        ).encode()
        checksum.update(descriptor + b"\0" + data + b"\0")
    return checksum.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    args = parser.parse_args()
    value = fingerprint(args.root)
    print(value)
    if output := os.environ.get("GITHUB_OUTPUT"):
        with open(output, "a") as stream:
            stream.write(f"key=bootstrap-v1-linux-64-{value}\n")


if __name__ == "__main__":
    main()
