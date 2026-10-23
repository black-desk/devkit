"""Exercise automatic notmuch discovery and message listing in a real terminal."""

import fcntl
import os
from pathlib import Path
import pty
import select
import signal
import struct
import subprocess
import tempfile
import termios
import time

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    env = dict(os.environ)
    for key in ("NOTMUCH_DATABASE", "NOTMUCH_PROFILE"):
        env.pop(key, None)
    env.update(
        HOME=str(root),
        XDG_CONFIG_HOME=str(root / "config"),
        XDG_DATA_HOME=str(root / "data"),
        XDG_CACHE_HOME=str(root / "cache"),
        XDG_STATE_HOME=str(root / "state"),
        XDG_RUNTIME_DIR=str(root),
        NOTMUCH_CONFIG=str(root / "notmuch-config"),
        TERM="xterm-256color",
    )
    mail = root / "mail"
    for name in ("cur", "new", "tmp"):
        (mail / name).mkdir(parents=True)
    (mail / "cur/message:2,S").write_text(
        "From: sender@example.invalid\n"
        "To: devkit@example.invalid\n"
        "Subject: devkit automatic discovery\n"
        "Message-ID: <aerc-discovery@example.invalid>\n"
        "Date: Wed, 21 Oct 2026 10:00:00 +0000\n\n"
        "Offline discovery test.\n"
    )
    Path(env["NOTMUCH_CONFIG"]).write_text(
        f"[database]\npath={mail}\n"
        "[user]\nname=Devkit Test\nprimary_email=devkit@example.invalid\n"
        "[new]\ntags=inbox;\n"
    )
    subprocess.run(["notmuch", "new"], env=env, check=True)
    config = root / "config/aerc"
    config.mkdir(parents=True)
    (config / "accounts.conf").write_text(
        "[Local]\nsource = notmuch://\n"
        "from = Devkit Test <devkit@example.invalid>\n"
        f"query-map = {config / 'query-map'}\n"
        "default = Inbox\ncheck-mail = 0\n"
    )
    (config / "accounts.conf").chmod(0o600)
    (config / "query-map").write_text("Inbox=tag:inbox\n")
    log = root / "aerc.log"
    (config / "aerc.conf").write_text(f"[general]\nlog-file={log}\n")
    pid, terminal = pty.fork()
    if pid == 0:
        os.execvpe("aerc", ["aerc", "-I"], env)
    output = bytearray()
    try:
        fcntl.ioctl(terminal, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 120, 0, 0))
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            if select.select([terminal], [], [], 0.2)[0]:
                try:
                    chunk = os.read(terminal, 65536)
                except OSError:
                    break
                if not chunk:
                    break
                output.extend(chunk)
                if b"devkit automatic discovery" in output:
                    break
        else:
            raise AssertionError("aerc did not display the indexed message")
        assert (
            b"devkit automatic discovery" in output
        ), "aerc exited without listing mail"
        assert "[Local] connected." in log.read_text(), log.read_text()
        assert "No database found" not in log.read_text(), log.read_text()
        print("aerc automatic notmuch discovery and message listing: OK")
    except BaseException:
        if log.exists():
            print(log.read_text())
        raise
    finally:
        os.kill(pid, signal.SIGTERM)
        os.waitpid(pid, 0)
        os.close(terminal)
