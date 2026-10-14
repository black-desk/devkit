#!/usr/bin/env python3
"""Stage explicitly named development interfaces; leave runtime files in place."""

import argparse
import json
import os
import re
from pathlib import Path
import shutil

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("prefix", type=Path)
parser.add_argument("--include", action="append", default=[])
parser.add_argument("--library", action="append", default=[])
parser.add_argument(
    "--runtime-library",
    action="append",
    default=[],
    help="reviewed runtime filenames that end in .so",
)
parser.add_argument("--metadata", action="append", default=[])
parser.add_argument(
    "--all",
    action="store_true",
    help="stage newly installed top-level development interfaces",
)
args = parser.parse_args()
prefix = args.prefix.resolve()
dev = prefix / "lib/devkit"
dependencies = set()
for record in (prefix / "conda-meta").glob("*.json"):
    dependencies.update(json.loads(record.read_text()).get("files", []))


def staged_link_destination(path):
    relative = path.relative_to(prefix).as_posix()
    if relative in dependencies:
        return path
    if relative.startswith(
        ("include/", "lib/pkgconfig/", "lib/cmake/", "share/cmake/", "lib/icu/")
    ) or relative.startswith("lib/objects-"):
        return dev / relative
    if path.parent == prefix / "lib" and path.name.endswith((".a", ".la")):
        return dev / relative
    return path


def move(relative):
    source = prefix / relative
    if not source.exists() and not source.is_symlink():
        raise FileNotFoundError(source)
    files = [source] if not source.is_dir() else list(source.rglob("*"))
    for path in files:
        if path.relative_to(prefix).as_posix() in dependencies:
            raise RuntimeError(f"refusing to move dependency-owned file: {path}")
    target = dev / relative
    if target.exists() or target.is_symlink():
        raise FileExistsError(target)
    target.parent.mkdir(parents=True, exist_ok=True)
    if source.is_symlink():
        original = Path(os.path.abspath(source.parent / source.readlink()))
        if original.is_relative_to(prefix):
            original = staged_link_destination(original)
        source.unlink()
        target.symlink_to(os.path.relpath(original, target.parent))
    else:
        shutil.move(str(source), target)
    return target


if args.all:
    # Only files not owned by installed input packages belong to this build.
    # Resource headers/modules under lib/clang, lib/perl5, etc. are runtime/tool
    # interfaces and are intentionally outside these discovery directories.
    for root in [
        prefix / "include",
        prefix / "lib/pkgconfig",
        prefix / "lib/cmake",
        prefix / "share/cmake",
        prefix / "lib/icu",
        *sorted((prefix / "lib").glob("objects-*")),
    ]:
        if root.exists():
            for source in sorted(root.rglob("*")):
                if source.is_file() or source.is_symlink():
                    relative = source.relative_to(prefix).as_posix()
                    if relative not in dependencies:
                        args.metadata.append(relative)
    stems = set()
    for source in (prefix / "lib").glob("lib*"):
        if source.is_dir() or source.relative_to(prefix).as_posix() in dependencies:
            continue
        for suffix in [".so", ".a", ".la"]:
            if suffix in source.name:
                stems.add(source.name[3:].split(suffix, 1)[0])
                break
    args.library.extend(sorted(stems))

for include in args.include:
    move("include/" + include)

# Alias chains (libunwind.so -> libgcc_s.so, libcurses.so -> libncurses.so)
# must be resolved before deleting any public unversioned linker entry.
runtime_targets = {
    source: source.resolve(strict=True)
    for source in (prefix / "lib").glob("lib*.so")
    if source.is_symlink() and source.relative_to(prefix).as_posix() not in dependencies
}

for library in args.library:
    candidates = sorted((prefix / "lib").glob(f"lib{library}.*"))
    if not candidates:
        raise FileNotFoundError(f"no library interfaces for {library}")
    for source in candidates:
        if source.relative_to(prefix).as_posix() in dependencies:
            continue
        name = source.name
        if name.endswith((".a", ".la")):
            path = move("lib/" + name)
            if name.endswith(".la"):
                path.write_text(
                    path.read_text().replace(str(prefix) + "/lib", str(dev) + "/lib")
                )
        elif ".so" in name:
            target = dev / "lib" / name
            target.parent.mkdir(parents=True, exist_ok=True)
            if target.exists() or target.is_symlink():
                raise FileExistsError(target)
            if name.endswith(".so"):
                if source.is_symlink():
                    runtime = runtime_targets[source]
                    source.unlink()
                    target.symlink_to(os.path.relpath(runtime, target.parent))
                else:
                    with source.open("rb") as stream:
                        elf = stream.read(4) == b"\x7fELF"
                    if elf and name in args.runtime_library:
                        target.symlink_to(os.path.relpath(source, target.parent))
                        continue
                    if elf:
                        raise RuntimeError(
                            f"unversioned runtime library needs review: {source}"
                        )
                    # Linker scripts (not runtime ELF) are development interfaces.
                    path = move("lib/" + name)
                    path.write_text(
                        path.read_text().replace(
                            str(prefix) + "/lib/", str(dev) + "/lib/"
                        )
                    )
            else:
                # Preserve SONAME links and real versioned files in public lib.
                target.symlink_to(os.path.relpath(source, target.parent))

for metadata in dict.fromkeys(args.metadata):
    target = move(metadata)
    files = [target] if target.is_file() else list(target.rglob("*"))
    for path in files:
        if path.suffix == ".pc":
            lines = path.read_text().splitlines()
            lines = [
                (
                    "prefix=${pcfiledir}/../.."
                    if re.match(r"^\s*prefix\s*=", line)
                    else (
                        "exec_prefix=${prefix}"
                        if re.match(r"^\s*exec_prefix\s*=", line)
                        else line.replace(
                            str(prefix) + "/include", "${prefix}/include"
                        ).replace(str(prefix) + "/lib", "${prefix}/lib")
                    )
                )
                for line in lines
            ]
            # Some upstream metadata (notably keyutils) refers to ${prefix}
            # without defining it. Do not leave its paths rooted at /include.
            if not any(line.startswith("prefix=") for line in lines):
                lines.insert(0, "prefix=${pcfiledir}/../..")
            path.write_text("\n".join(lines) + "\n")
        elif path.suffix in [".cmake", ".inc"]:
            # Upstream relative exports naturally compute the hidden prefix.
            # Correct only literal configured development paths, not runtime paths.
            text = path.read_text()
            text = text.replace(str(prefix) + "/include/", str(dev) + "/include/")
            text = text.replace(str(prefix) + "/lib/lib", str(dev) + "/lib/lib")
            if path.suffix == ".cmake":
                # Exported executable targets still live in public bin. Rewrite
                # their relative locations instead of publishing a shared bin
                # alias that both LLVM and PCRE2 would have to own.
                text = re.sub(
                    r"(\$\{[^}]*prefix[^}]*\})/bin(?=[/\"\s)])",
                    r"\1/../../bin",
                    text,
                    flags=re.IGNORECASE,
                )
                # Autotools libxml2 exports a library search directory rather
                # than an imported filename. Keep executable/runtime paths public.
                text = re.sub(
                    r"(set\(\w*(?:LIBRARY_DIRS?|LIBDIR)\s+\"?)"
                    + re.escape(str(prefix))
                    + r"/lib(?=[\"\s)])",
                    lambda match: match[1] + str(dev) + "/lib",
                    text,
                )
                # Keep configured absolute exports usable when an installation
                # is moved, without depending on conda prefix substitution.
                for root in [dev, prefix]:
                    relative = os.path.relpath(root, path.parent)
                    reference = "${CMAKE_CURRENT_LIST_DIR}/" + relative
                    text = re.sub(
                        re.escape(str(root)) + r'(?=/|["\s)])',
                        lambda match: reference,
                        text,
                    )
            elif metadata.startswith("lib/icu/"):
                text = text.replace(
                    "$(prefix)/include/", "$(prefix)/lib/devkit/include/"
                )
                text = text.replace(
                    "${prefix}/include/", "${prefix}/lib/devkit/include/"
                )
                text = text.replace("-L$(libdir)", "-L$(prefix)/lib/devkit/lib")
                text = text.replace(
                    "pkglibdir = $(libdir)/", "pkglibdir = $(prefix)/lib/devkit/lib/"
                )
            path.write_text(text)
