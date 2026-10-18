"""Adjust consumer metadata where upstream install options are insufficient."""

import os
from pathlib import Path

prefix = Path(os.environ["PREFIX"])
dev = prefix / "lib/devkit"
for path in (dev / "lib/cmake/expat-2.8.5").glob("*.cmake"):
    text = path.read_text().replace(
        "${_IMPORT_PREFIX}/include", "${_IMPORT_PREFIX}/include/expat-2.8.5"
    )
    path.write_text(text)
