import importlib.metadata
import os
from pathlib import Path
import sys

import greenlet
import greenlet._greenlet
import msgpack
import msgpack._cmsgpack
import pynvim

prefix = Path(os.environ["PREFIX"])
tool = prefix / "lib/devkit/share/devkit/python-tools/pynvim"
assert Path(sys.prefix) == tool, (sys.prefix, tool)
assert Path(sys.base_prefix).is_relative_to(prefix / "lib/uv-python")
assert importlib.metadata.version("pynvim") == "0.6.0"
assert importlib.metadata.version("greenlet") == "3.5.6"
assert importlib.metadata.version("msgpack") == "1.2.3"
assert msgpack.Packer.__module__ == "msgpack._cmsgpack"
payload = {"message": "devkit RPC", "values": [1, 2, 3]}
assert msgpack.unpackb(msgpack.packb(payload), raw=False) == payload
assert greenlet.greenlet(lambda: "devkit greenlet").switch() == "devkit greenlet"

nvim = pynvim.attach(
    "child",
    argv=["nvim", "--embed", "--headless", "-u", "NONE", "-i", "NONE", "-n"],
)
try:
    nvim.current.buffer[:] = ["devkit RPC", "second line"]
    assert nvim.current.buffer[:] == ["devkit RPC", "second line"]
    assert nvim.exec_lua("return 6 * 7") == 42
    # No python3_host_prog override: Neovim must discover pynvim-python on PATH.
    assert nvim.eval("has('python3')") == 1
    nvim.command(
        "python3 import sys, vim; "
        "vim.vars['devkit_python_prefix'] = sys.prefix; "
        "vim.current.buffer[0] = 'devkit Python provider'"
    )
    assert nvim.vars["devkit_python_prefix"] == str(tool)
    assert nvim.current.buffer[0] == "devkit Python provider"
finally:
    try:
        nvim.command("qa!")
    except EOFError:
        pass
    nvim.close()
print("pynvim native extensions, embedded RPC and Python provider: OK")
