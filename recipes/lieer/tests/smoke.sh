#!/usr/bin/env bash
set -euxo pipefail

gmi --help
"${PREFIX}/lib/devkit/share/devkit/python-tools/lieer/bin/python" -I tests/runtime.py
# Check the source-built extension separately from imported-wheel exceptions.
readelf -d "${PREFIX}/lib/devkit/share/devkit/python-tools/lieer/lib/python3.14/site-packages/notmuch2/"_capi*.so | grep -F '(RUNPATH)'
