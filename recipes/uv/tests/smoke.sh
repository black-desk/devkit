#!/usr/bin/env bash
set -euxo pipefail

export UV_NO_CONFIG=1
export UV_OFFLINE=1
export UV_PYTHON_DOWNLOADS=never
export UV_CACHE_DIR="${PWD}/.uv-cache"
export UV_PYTHON_INSTALL_DIR="${PWD}/managed-python"
export UV_PYTHON_BIN_DIR="${PWD}/python-bin"
export UV_TOOL_DIR="${PWD}/tools"
export UV_TOOL_BIN_DIR="${PWD}/tool-bin"

test "$(command -v uv)" = "${PREFIX}/bin/uv"
test "$(command -v uvx)" = "${PREFIX}/bin/uvx"
test "$(uv python dir)" = "${UV_PYTHON_INSTALL_DIR}"
test "$(uv python dir --bin)" = "${UV_PYTHON_BIN_DIR}"
test "$(uv tool dir)" = "${UV_TOOL_DIR}"
test "$(uv tool dir --bin)" = "${UV_TOOL_BIN_DIR}"
uv tool list > tools.txt 2>&1
grep -Fx 'No tools installed' tools.txt

# Project creation and bundled Python download metadata work without an
# installed interpreter or network access.
uv init --bare --no-workspace --vcs none --no-pin-python --python 3.13 sample
test -s sample/pyproject.toml
grep -Fx 'name = "sample"' sample/pyproject.toml
uv python list --only-downloads > python-downloads.txt
grep -F 'cpython-3.13.' python-downloads.txt

# A conda-owned executable must refuse to update itself.
if uv self update > self-update.txt 2>&1; then
  printf 'error: uv self update unexpectedly succeeded\n' >&2
  exit 1
fi
grep -F 'installed through an external package manager and cannot update itself' self-update.txt

for binary in uv uvx; do
  test -s "${PREFIX}/share/bash-completion/completions/${binary}"
  test -s "${PREFIX}/share/fish/vendor_completions.d/${binary}.fish"
  test -s "${PREFIX}/share/zsh/site-functions/_${binary}"
done
