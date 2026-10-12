#!/usr/bin/env python3
"""Remove generated outputs, retaining source caches without traversing them."""

import errno
import os
from pathlib import Path
import stat
import sys


def clean(root: Path) -> None:
    if not root.exists():
        return
    directories = []
    for current, children, files in os.walk(root, followlinks=False):
        directory = Path(current)
        # Go's module cache creates read-only directories. Removing entries
        # requires directory write permission, not changing hardlinked files.
        directory.chmod(stat.S_IMODE(directory.stat().st_mode) | stat.S_IWUSR)
        directories.append(directory)
        descend = []
        for name in children:
            path = directory / name
            if name == "src_cache":
                continue
            if path.is_symlink():
                path.unlink()
            else:
                descend.append(name)
        children[:] = descend
        for name in files:
            (directory / name).unlink()
    for directory in reversed(directories):
        if directory == root:
            continue
        try:
            directory.rmdir()
        except OSError as error:
            # Ancestors of retained src_cache directories remain nonempty.
            if error.errno not in (errno.ENOTEMPTY, errno.EEXIST):
                raise


if __name__ == "__main__":
    clean(Path(sys.argv[1]))
