#!/usr/bin/env bash
set -euxo pipefail
lua-language-server --version | grep -F 3.19.2
printf 'local answer=42\nprint(answer)\n' >sample.lua
python3 tests/lsp.py --document sample.lua --language lua --format -- lua-language-server --logpath="${PWD}/logs" --metapath="${PWD}/meta"
ldd "$(readlink -f "${PREFIX}/bin/lua-language-server")" >libraries.txt
grep -F 'libc++.so.1 =>' libraries.txt | grep -F "${PREFIX}/"
if grep -F libstdc++ libraries.txt; then exit 1; fi
