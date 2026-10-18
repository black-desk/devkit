"""Adjust consumer metadata where upstream install options are insufficient."""

import os
from pathlib import Path
import re
import shutil

prefix = Path(os.environ["PREFIX"])
dev = prefix / "lib/devkit"
# Keep curl-config's generated dependency list; only relocate its query paths.
source = prefix / "bin/curl-config"
path = dev / "libexec/curl/bin/curl-config"
path.parent.mkdir(parents=True, exist_ok=True)
shutil.move(str(source), path)
text = path.read_text()
text = re.sub(
    r"(?m)^prefix=.*$",
    'prefix="$(CDPATH= cd -- "$(dirname -- "$0")/../../../../.." && pwd)"',
    text,
    count=1,
)
text = re.sub(r"(?m)^exec_prefix=.*$", 'exec_prefix="${prefix}"', text, count=1)
text = re.sub(
    r"(?m)^includedir=.*$",
    'includedir="${prefix}/lib/devkit/include/curl-8.22.0"',
    text,
    count=1,
)
text = text.replace(str(prefix), "${prefix}")
# The upstream --ca branch single-quotes the configured literal path.
text = re.sub(
    r"(--ca\)\s*\n\s*)echo .*",
    lambda m: m[1] + 'echo "${prefix}/lib/devkit/etc/ssl/certs/ca-certificates.crt"',
    text,
)
text = re.sub(
    r"(--cc\)\s*\n\s*)echo .*",
    lambda m: m[1] + 'echo "${prefix}/bin/clang"',
    text,
)
path.write_text(text)
