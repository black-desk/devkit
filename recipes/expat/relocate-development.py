"""Relocate this recipe's development interfaces after upstream installation."""

import os
from pathlib import Path
import re
import shutil

prefix = Path(os.environ["PREFIX"])
dev = prefix / "lib/devkit"
(dev / "lib").mkdir(parents=True, exist_ok=True)
# Resolve every alias before removing any public linker symlinks.
libraries = [
    path for stem in ["expat"] for path in (prefix / "lib").glob("lib" + stem + ".*")
]
shared = {
    path: path.resolve(strict=True)
    for path in libraries
    if ".so" in path.name and path.is_symlink()
}
for path in libraries:
    target = dev / "lib" / path.name
    if path.name.endswith((".a", ".la")):
        assert not target.exists(), target
        if path.is_symlink():
            original = Path(os.path.abspath(path.parent / path.readlink()))
            if original in libraries:
                original = dev / "lib" / original.name
            target.symlink_to(os.path.relpath(original, target.parent))
            path.unlink()
        else:
            shutil.move(str(path), target)
        if target.suffix == ".la":
            target.write_text(
                re.sub(
                    re.escape(str(prefix)) + r"/lib(?!/devkit)(?=/|['\s])",
                    str(dev) + "/lib",
                    target.read_text(),
                )
            )
    elif ".so" in path.name:
        if path in shared:
            runtime = shared[path]
            target.symlink_to(os.path.relpath(runtime, target.parent))
            if path.name.endswith(".so"):
                path.unlink()
        else:
            with path.open("rb") as stream:
                elf = stream.read(4) == b"\x7fELF"
            if not path.name.endswith(".so"):
                target.symlink_to(os.path.relpath(path, target.parent))
            else:
                assert not elf, ("unreviewed unversioned runtime ELF", path)
                shutil.move(str(path), target)
                target.write_text(
                    target.read_text().replace(
                        str(prefix) + "/lib/", str(dev) + "/lib/"
                    )
                )
import re

# Change only location variables; upstream Libs/Requires retain their generated dependencies.
for name in ["expat"]:
    path = prefix / "lib/pkgconfig" / (name + ".pc")
    target = dev / "lib/pkgconfig" / path.name
    target.parent.mkdir(parents=True, exist_ok=True)
    if path.is_file():
        assert not target.exists(), target
        shutil.move(str(path), target)
    assert target.is_file(), target
    text = target.read_text()
    values = {
        "prefix": "${pcfiledir}/../..",
        "exec_prefix": "${prefix}",
        "libdir": "${prefix}/lib",
        "includedir": "${prefix}/include/expat-2.8.5",
    }
    lines = text.splitlines(keepends=True)
    for key, value in values.items():
        matches = [
            i for i, line in enumerate(lines) if re.match(r"^" + key + r"\s*=", line)
        ]
        if matches:
            assert len(matches) == 1, (target, key)
            lines[matches[0]] = key + "=" + value + "\n"
        elif key == "prefix":
            lines.insert(0, key + "=" + value + "\n")
    text = "".join(lines)
    # Recorded input prefixes become metadata-relative paths, preserving library order.
    text = text.replace(str(prefix) + "/lib/devkit", "${prefix}")
    text = text.replace(str(prefix) + "/lib", "${libdir}")
    text = text.replace(str(prefix) + "/include", "${includedir}")
    target.write_text(text)
# A moved export's computed _IMPORT_PREFIX/PACKAGE_PREFIX_DIR now denotes lib/devkit.
for name in ["expat-2.8.5"]:
    source = prefix / "lib/cmake" / name
    target = dev / "lib/cmake" / name
    target.parent.mkdir(parents=True, exist_ok=True)
    if source.exists():
        assert not target.exists(), target
        shutil.move(str(source), target)
    assert target.is_dir(), target
    for path in target.rglob("*.cmake"):
        text = path.read_text()
        for variable in ["_IMPORT_PREFIX", "PACKAGE_PREFIX_DIR"]:
            text = text.replace(
                "${" + variable + "}/lib/devkit/", "${" + variable + "}/"
            )
            text = text.replace(
                "${" + variable + "}/bin/", "${" + variable + "}/../../bin/"
            )
        runtime = "${CMAKE_CURRENT_LIST_DIR}/" + os.path.relpath(prefix, path.parent)
        text = text.replace(str(prefix), runtime)
        path.write_text(text)
for path in (dev / "lib/cmake/expat-2.8.5").glob("*.cmake"):
    text = path.read_text().replace(
        "${_IMPORT_PREFIX}/include", "${_IMPORT_PREFIX}/include/expat-2.8.5"
    )
    path.write_text(text)
