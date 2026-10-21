#!/usr/bin/env python3
"""Exercise an installed stdio language server with bounded protocol requests."""

import argparse
import json
from pathlib import Path
import queue
import subprocess
import threading


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--document", required=True)
    parser.add_argument("--language", required=True)
    parser.add_argument("--format", action="store_true")
    parser.add_argument("--shutdown-closes", action="store_true")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    document = Path(args.document).resolve()
    messages = queue.Queue()
    with open("lsp-stderr.log", "w") as log:
        process = subprocess.Popen(
            command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=log
        )

        def send(message):
            payload = json.dumps({"jsonrpc": "2.0", **message}).encode()
            process.stdin.write(
                f"Content-Length: {len(payload)}\r\n\r\n".encode() + payload
            )
            process.stdin.flush()

        def reader():
            try:
                while True:
                    headers = {}
                    while True:
                        line = process.stdout.readline()
                        if not line:
                            raise EOFError("server closed stdout")
                        if line in (b"\r\n", b"\n"):
                            break
                        key, value = line.decode().split(":", 1)
                        headers[key.lower()] = value.strip()
                    messages.put(
                        json.loads(process.stdout.read(int(headers["content-length"])))
                    )
            except Exception as error:
                messages.put(error)

        threading.Thread(target=reader, daemon=True).start()

        def response(identifier):
            while True:
                item = messages.get(timeout=60)
                if isinstance(item, Exception):
                    raise item
                if "method" in item and "id" in item:
                    result = [] if item["method"] == "workspace/configuration" else None
                    send({"id": item["id"], "result": result})
                elif item.get("id") == identifier:
                    assert "error" not in item, item
                    return item.get("result")

        try:
            send(
                {
                    "id": 1,
                    "method": "initialize",
                    "params": {
                        "processId": None,
                        "rootUri": document.parent.as_uri(),
                        "workspaceFolders": [
                            {"uri": document.parent.as_uri(), "name": "smoke"}
                        ],
                        "capabilities": {},
                        "initializationOptions": {},
                    },
                }
            )
            result = response(1)
            assert isinstance(result["capabilities"], dict), result
            send({"method": "initialized", "params": {}})
            send(
                {
                    "method": "textDocument/didOpen",
                    "params": {
                        "textDocument": {
                            "uri": document.as_uri(),
                            "languageId": args.language,
                            "version": 1,
                            "text": document.read_text(),
                        }
                    },
                }
            )
            if args.format:
                send(
                    {
                        "id": 2,
                        "method": "textDocument/formatting",
                        "params": {
                            "textDocument": {"uri": document.as_uri()},
                            "options": {"tabSize": 2, "insertSpaces": True},
                        },
                    }
                )
                edits = response(2)
                assert edits and all("newText" in edit for edit in edits), edits
            send({"id": 3, "method": "shutdown", "params": None})
            try:
                response(3)
            except EOFError:
                if not args.shutdown_closes:
                    raise
            else:
                send({"method": "exit", "params": None})
            process.stdin.close()
            assert process.wait(timeout=15) == 0
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
    print(
        "LSP initialize, document open, shutdown"
        + (" and formatting" if args.format else "")
        + ": OK"
    )


if __name__ == "__main__":
    main()
