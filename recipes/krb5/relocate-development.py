"""Adjust consumer metadata where upstream install options are insufficient."""

import os
from pathlib import Path
import re
import shutil

prefix = Path(os.environ["PREFIX"])
dev = prefix / "lib/devkit"
source = prefix / "bin/krb5-config"
path = dev / "libexec/krb5/bin/krb5-config"
path.parent.mkdir(parents=True, exist_ok=True)
shutil.move(str(source), path)
text = path.read_text()
text = re.sub(
    r"(?m)^prefix=.*$",
    'prefix="$(CDPATH= cd -- "$(dirname -- "$0")/../../../../.." && pwd)"',
    text,
    count=1,
)
text = re.sub(r"(?m)^exec_prefix=.*$", "exec_prefix=${prefix}", text, count=1)
text = re.sub(
    r"(?m)^includedir=.*$",
    "includedir=${prefix}/lib/devkit/include/krb5-1.22.2",
    text,
    count=1,
)
text = re.sub(r"(?m)^libdir=.*$", "libdir=${prefix}/lib/devkit/lib", text, count=1)
path.write_text(text)
