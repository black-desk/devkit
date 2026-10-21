"""Exercise installed clangd through its LSP transport without an editor."""

import json
import os
from pathlib import Path
import select
import subprocess
import time

prefix = Path(os.environ["PREFIX"])
clangd = prefix / "bin/clangd"
version = subprocess.check_output([clangd, "--version"], text=True)
assert "23.1.3" in version, version
root = Path("workspace").resolve()
root.mkdir()
source = root / "main.cpp"
text = """#include <stddef.h>
int twice(int value) { return value * 2; }
int main() {
    size_t count = 2;
    return twice(static_cast<int>(count));
}
int *empty() { return 0; }
"""
source.write_text(text)
(root / ".clangd").write_text(
    "Diagnostics:\n  ClangTidy:\n    Add: modernize-use-nullptr\n"
)
(root / "compile_commands.json").write_text(
    json.dumps(
        [
            {
                "directory": str(root),
                "file": str(source),
                "arguments": [
                    str(prefix / "bin/clang++"),
                    "-std=c++17",
                    "-fsyntax-only",
                    str(source),
                ],
            }
        ]
    )
)
uri = source.as_uri()
buffer = b""


def send(method, params=None, request_id=None):
    message = {"jsonrpc": "2.0", "method": method}
    if params is not None:
        message["params"] = params
    if request_id is not None:
        message["id"] = request_id
    body = json.dumps(message).encode()
    server.stdin.write(f"Content-Length: {len(body)}\r\n\r\n".encode() + body)
    server.stdin.flush()


def receive(predicate):
    global buffer
    deadline = time.monotonic() + 60
    while time.monotonic() < deadline:
        if b"\r\n\r\n" in buffer:
            header, body = buffer.split(b"\r\n\r\n", 1)
            length = next(
                int(line.split(b":", 1)[1])
                for line in header.split(b"\r\n")
                if line.lower().startswith(b"content-length:")
            )
            if len(body) >= length:
                message = json.loads(body[:length])
                buffer = body[length:]
                if predicate(message):
                    return message
                continue
        ready, _, _ = select.select(
            [server.stdout], [], [], max(0, deadline - time.monotonic())
        )
        if ready:
            chunk = os.read(server.stdout.fileno(), 65536)
            assert chunk, "clangd closed its LSP output"
            buffer += chunk
    raise AssertionError("timed out waiting for clangd LSP response")


with Path("clangd.log").open("w") as log:
    server = subprocess.Popen(
        [clangd, "--background-index=false", "--clang-tidy", "--log=error"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=log,
        bufsize=0,
        env={**os.environ, "XDG_CONFIG_HOME": str(root / "config")},
    )
    try:
        send("initialize", {"rootUri": root.as_uri(), "capabilities": {}}, 1)
        response = receive(lambda message: message.get("id") == 1)
        assert response["result"]["capabilities"]["definitionProvider"], response
        send("initialized", {})
        send(
            "textDocument/didOpen",
            {
                "textDocument": {
                    "uri": uri,
                    "languageId": "cpp",
                    "version": 1,
                    "text": text,
                }
            },
        )
        diagnostics = receive(
            lambda message: message.get("method") == "textDocument/publishDiagnostics"
            and message["params"]["uri"] == uri
        )["params"]["diagnostics"]
        assert not any(item.get("severity") == 1 for item in diagnostics), diagnostics
        assert any(
            item.get("code") == "modernize-use-nullptr" for item in diagnostics
        ), diagnostics
        send(
            "textDocument/definition",
            {"textDocument": {"uri": uri}, "position": {"line": 4, "character": 12}},
            2,
        )
        locations = receive(lambda message: message.get("id") == 2)["result"]
        assert locations[0]["uri"] == uri, locations
        assert locations[0]["range"]["start"]["line"] == 1, locations
        send(
            "textDocument/didChange",
            {
                "textDocument": {"uri": uri, "version": 2},
                "contentChanges": [{"text": text + "int broken = missing_symbol;\n"}],
            },
        )
        diagnostics = receive(
            lambda message: message.get("method") == "textDocument/publishDiagnostics"
            and message["params"]["uri"] == uri
            and any(
                "missing_symbol" in item["message"]
                for item in message["params"]["diagnostics"]
            )
        )["params"]["diagnostics"]
        assert any(item.get("severity") == 1 for item in diagnostics), diagnostics
        send("shutdown", request_id=3)
        receive(lambda message: message.get("id") == 3)
        send("exit")
        server.wait(timeout=10)
        assert server.returncode == 0, server.returncode
    finally:
        if server.poll() is None:
            server.kill()
            server.wait()
        server.stdin.close()
        server.stdout.close()

print("clangd LSP: resource headers, clang-tidy, definitions and diagnostics: OK")
