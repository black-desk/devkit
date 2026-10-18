"""Adjust consumer metadata where upstream install options are insufficient."""

import os
from pathlib import Path

prefix = Path(os.environ["PREFIX"])
dev = prefix / "lib/devkit"
path = dev / "lib/pkgconfig/lzo2.pc"
text = path.read_text()
assert "-I${includedir}/lzo" in text
path.write_text(
    text.replace("-I${includedir}/lzo", "-I${includedir} -I${includedir}/lzo")
)
