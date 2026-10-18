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
    path
    for stem in ["ev"]
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
