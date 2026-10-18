"""Relocate this recipe's development interfaces after upstream installation."""

import os
from pathlib import Path
import re
import shutil

prefix = Path(os.environ["PREFIX"])
dev = prefix / "lib/devkit"
(dev / "lib").mkdir(parents=True, exist_ok=True)
# LLVM's native install options already place headers and package configs in lib/devkit.
# Move only the compiler's libraries; do not touch dependencies or compiler-rt resources.
stems = sorted(
    {
        path.name[3:].split(".so", 1)[0].split(".a", 1)[0]
        for pattern in [
            "libLLVM*",
            "libclang*",
            "liblld*",
            "libLTO*",
            "libRemarks*",
        ]
        for path in (prefix / "lib").glob(pattern)
        if path.is_file() or path.is_symlink()
    }
)
# Resolve every alias before removing any public linker symlinks.
libraries = [
    path
    for stem in stems
    for path in (prefix / "lib").glob("lib" + stem + ".*")
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
for package in ["llvm", "clang", "lld"]:
    for path in (dev / "lib/cmake" / package).rglob("*.cmake"):
        text = path.read_text()
        # Archives moved; runtime DSOs and exported executable paths did not.
        lines = text.splitlines(keepends=True)
        for i, line in enumerate(lines):
            if ".a" in line and "/lib/" in line:
                lines[i] = line.replace("/lib/", "/lib/devkit/lib/")
        text = "".join(lines)
        if path.name == "LLVMConfig.cmake":
            text = text.replace(
                'set(LLVM_LIBRARY_DIRS "${LLVM_INSTALL_PREFIX}/lib',
                'set(LLVM_LIBRARY_DIRS "${LLVM_INSTALL_PREFIX}/lib/devkit/lib',
            )
            text = text.replace(
                'set(LLVM_LIBRARY_DIR "${LLVM_INSTALL_PREFIX}/lib',
                'set(LLVM_LIBRARY_DIR "${LLVM_INSTALL_PREFIX}/lib/devkit/lib',
            )
        path.write_text(text)
