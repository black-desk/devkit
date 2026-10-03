import bz2
import ctypes
import hashlib
import lzma
import os
from pathlib import Path
import readline
import sqlite3
import ssl
import sys
import sysconfig
import zlib

prefix = Path(os.environ["PREFIX"])
root = prefix / "lib/uv-python/cpython-3.14.8-linux-x86_64-gnu"
assert sys.version_info[:3] == (3, 14, 8)
assert Path(sys.executable).resolve() == root / "bin/python3.14"
assert Path(sys.prefix).resolve() == root
assert Path(sys.base_prefix).resolve() == root
assert (root / "BUILD").read_text().strip() == "20261001"
assert (
    "devkit conda channel" in (root / "lib/python3.14/EXTERNALLY-MANAGED").read_text()
)
assert not (prefix / "lib/uv-python/.lock").exists()
assert not (prefix / "lib/uv-python/.gitignore").exists()

# uv's sysconfig adjustments must survive conda prefix replacement. These
# locations are also how downstream extension builds find Python's headers.
for path in sysconfig.get_paths().values():
    assert Path(path).resolve().is_relative_to(root), path
for name in ("LIBDIR", "LIBPL", "INCLUDEPY", "BINDIR"):
    path = Path(sysconfig.get_config_var(name)).resolve()
    assert path.is_relative_to(root) and path.exists(), (name, path)
assert (Path(sysconfig.get_path("include")) / "Python.h").is_file()

payload = b"devkit-python-runtime" * 100
for module in (bz2, lzma, zlib):
    assert module.decompress(module.compress(payload)) == payload
assert hashlib.sha256(payload).hexdigest()
assert ctypes.CDLL(None).getpid() == os.getpid()
with sqlite3.connect(":memory:") as connection:
    assert connection.execute("select 6 * 7").fetchone() == (42,)
context = ssl.create_default_context()
assert context.verify_mode == ssl.CERT_REQUIRED
assert readline.__doc__
print(sys.version)
print(ssl.OPENSSL_VERSION)
print("Runtime and relocated sysconfig paths verified")
