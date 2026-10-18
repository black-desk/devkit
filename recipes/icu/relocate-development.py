"""Adjust consumer metadata where upstream install options are insufficient."""

import os
from pathlib import Path
import re
import shutil

prefix = Path(os.environ["PREFIX"])
dev = prefix / "lib/devkit"
config = dev / "lib/icu/78.3"
path = config / "Makefile.inc"
text = path.read_text()
values = {
    "exec_prefix": "$(prefix)",
    "libdir": "$(prefix)/lib/devkit/lib",
    "includedir": "$(prefix)/lib/devkit/include/icu-78.3",
    "pkglibdir": "$(prefix)/lib/devkit/lib/$(PACKAGE)$(ICULIBSUFFIX)/$(VERSION)",
    "AR": "llvm-ar",
    "CC": "clang",
    "CPP": "clang -E",
    "CXX": "clang++",
    "RANLIB": "llvm-ranlib",
}
for key, value in values.items():
    text, count = re.subn(r"(?m)^" + key + r" = .*$", key + " = " + value, text)
    assert count == 1, (path, key, count)
text = text.replace("-I$(prefix)/include", "-I$(prefix)/lib/devkit/include/icu-78.3")
path.write_text(text)
path = config / "pkgdata.inc"
text = path.read_text()
values = {
    "COMPILE": "clang -O2 -c",
    "GENLIB": "clang -shared -Wl,-Bsymbolic",
    "LIBFLAGS": "-I" + str(dev / "include/icu-78.3") + " -DPIC -fPIC",
    "AR": "llvm-ar",
    "RANLIB": "llvm-ranlib",
    "INSTALL_CMD": "install -c",
}
for key, value in values.items():
    text, count = re.subn(r"(?m)^" + key + r"=.*$", key + "=" + value, text)
    assert count == 1, (path, key, count)
path.write_text(text)

source = prefix / "bin/icu-config"
path = dev / "libexec/icu/bin/icu-config"
path.parent.mkdir(parents=True, exist_ok=True)
shutil.move(str(source), path)
text = path.read_text()
text = re.sub(
    r"(?m)^default_prefix=.*$",
    'default_prefix="$(CDPATH= cd -- "$(dirname -- "$0")/../../../../.." && pwd)"',
    text,
    count=1,
)
for key, value in {
    "CC": "clang",
    "CXX": "clang++",
    "CPP": "clang -E",
    "AR": "llvm-ar",
    "RANLIB": "llvm-ranlib",
    "CFLAGS": "-O2",
    "CXXFLAGS": "-O2 -std=c++17",
    "CPPFLAGS": "",
    "LDFLAGS": "",
}.items():
    text = re.sub(r"(?m)^" + key + r"=.*$", key + '="' + value + '"', text)
# --detect-prefix independently inferred bin/.. in upstream's public layout.
# This helper now lives five levels below the environment root.
text = text.replace(
    'HERE=`echo $0 | sed -e "s/$ME//g"`',
    'HERE="$(CDPATH= cd -- "$(dirname -- "$0")/../../../../.." && pwd)"',
)
text = text.replace("${HERE}/../lib/", "${HERE}/lib/devkit/lib/")
text = text.replace('prefix="${HERE}/.."', 'prefix="${HERE}"')
text = text.replace(str(prefix), "${prefix}")
path.write_text(text)
