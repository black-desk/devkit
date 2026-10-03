#!/usr/bin/env bash
set -euxo pipefail

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null
export XDG_CONFIG_HOME="${PWD}/config"
export XDG_CACHE_HOME="${PWD}/cache"
export XDG_DATA_HOME="${PWD}/data"
export UV_NO_CONFIG=1
export UV_OFFLINE=1
export UV_PYTHON_DOWNLOADS=never
export UV_CACHE_DIR="${PWD}/uv-cache"
export UV_TOOL_DIR="${PWD}/user-tools"
export UV_TOOL_BIN_DIR="${PWD}/user-bin"

b4 --version | grep -F 0.16.0
b4 --help
"${PREFIX}/share/devkit/python-tools/b4/bin/python" -I tests/runtime.py
uv tool list > user-tools.txt
test ! -s user-tools.txt
b4 --version

git init --quiet --initial-branch=main workflow
cd workflow
git config user.name 'Devkit Test'
git config user.email 'devkit@example.invalid'
git config commit.gpgsign false
git config b4.attestation-policy off
git config b4.checkmarks plain
printf 'before\n' > example.txt
git add example.txt
git commit --quiet -m 'Initial commit'
printf 'after\n' > example.txt
git commit --quiet -am 'Update example'
git format-patch -1 --stdout --add-header="Message-ID: <devkit-b4-test@example.invalid>" > ../input.mbx
git reset --hard HEAD~1
# Local input and disabled network-dependent enrichments keep this test offline.
b4 --offline-mode --no-interactive --no-stdin am --no-parent --no-cover --no-cache \
  -m ../input.mbx -o ../am-output
git am ../am-output/*.mbx
test "$(cat example.txt)" = after
test "$(git log -1 --format=%s)" = 'Update example'
