import errno
import fcntl
import os
from pathlib import Path
import pty
import select
import signal
import struct
import subprocess
import termios
import tempfile
import time

# Keep the Unix socket private and below the platform's socket path limit.
runtime_dir = tempfile.TemporaryDirectory(prefix="devkit-yazi-", dir="/tmp")
os.environ["XDG_RUNTIME_DIR"] = runtime_dir.name
root = Path.cwd()
for name in ("config", "cache", "state", "data"):
    path = root / name
    path.mkdir(exist_ok=True)
    os.environ[f"XDG_{name.upper()}_HOME"] = str(path)
os.environ["YAZI_CONFIG_HOME"] = str(root / "config/yazi")
os.environ["TERM"] = "xterm-256color"
workspace = root / "browse"
workspace.mkdir()
(workspace / "devkit-yazi-probe.txt").write_text("preview probe\n")
cwd_file = root / "last-directory"
client_id = str(os.getpid())
pid, terminal = pty.fork()
if pid == 0:
    os.execlp(
        "yazi",
        "yazi",
        "--client-id",
        client_id,
        "--cwd-file",
        str(cwd_file),
        str(workspace),
    )

fcntl.ioctl(terminal, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 120, 0, 0))
screen = bytearray()
quit_sent = False
status = None
deadline = time.monotonic() + 30
try:
    while time.monotonic() < deadline:
        ready, _, _ = select.select([terminal], [], [], 0.1)
        if ready:
            try:
                chunk = os.read(terminal, 65536)
            except OSError as error:
                if error.errno != errno.EIO:
                    raise
                chunk = b""
            screen.extend(chunk)
        if not quit_sent and b"devkit-yazi-probe.txt" in screen:
            # Exercise ya's local IPC as well as the embedded Lua/TUI startup.
            subprocess.run(
                ["ya", "emit-to", client_id, "quit"],
                check=True,
                timeout=10,
            )
            quit_sent = True
        finished, child_status = os.waitpid(pid, os.WNOHANG)
        if finished:
            status = child_status
            break
    assert quit_sent, screen.decode(errors="replace")
    assert status == 0, screen.decode(errors="replace")
    assert cwd_file.read_text().strip() == str(workspace)
finally:
    if status is None:
        os.kill(pid, signal.SIGKILL)
        os.waitpid(pid, 0)
    os.close(terminal)
    runtime_dir.cleanup()
print("Yazi terminal startup, file listing, ya IPC, and clean exit passed")
