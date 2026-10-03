import importlib.metadata
import os
from pathlib import Path
import sys
import tomllib

import _cffi_backend
import b4
import charset_normalizer
import dkim
import dns.resolver
import pygit2
from nacl.signing import SigningKey

prefix = Path(os.environ["PREFIX"]).resolve()
environment = prefix / "share/devkit/python-tools/b4"
assert Path(sys.prefix).resolve() == environment
assert Path(sys.base_prefix).resolve() == (
    prefix / "lib/uv-python/cpython-3.14.8-linux-x86_64-gnu"
)
assert Path(sys.executable).is_relative_to(environment)
for line in Path("requirements.lock").read_text().splitlines():
    if line and not line.startswith("#"):
        name, version = line.split("==")
        assert importlib.metadata.version(name) == version, name
receipt = tomllib.loads((environment / "uv-receipt.toml").read_text())
assert Path(receipt["tool"]["python"]) == prefix / "bin/python"
assert Path(receipt["tool"]["entrypoints"][0]["install-path"]) == prefix / "bin/b4"
assert not (environment.parent / ".lock").exists()
assert not (environment.parent / ".gitignore").exists()
key = SigningKey.generate()
message = b"devkit relocation test"
assert key.verify_key.verify(key.sign(message)) == message
repository = pygit2.init_repository("native-git", bare=True)
assert repository.is_bare
assert charset_normalizer.from_bytes(b"plain text").best() is not None
print("b4 runtime, pinned dependencies, native libraries, and relocation OK")
