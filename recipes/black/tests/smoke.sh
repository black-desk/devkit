#!/usr/bin/env bash
set -euxo pipefail
black --version | grep -F 26.10.1
printf 'x={"a":1,"b":2}\n' >sample.py
black --config /dev/null sample.py
black --config /dev/null --check sample.py
grep -Fx 'x = {"a": 1, "b": 2}' sample.py
"${PREFIX}/lib/devkit/share/devkit/python-tools/black/bin/python" -I -c 'import black; assert not black.COMPILED'
