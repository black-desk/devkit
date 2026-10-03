#!/usr/bin/env bash
set -euxo pipefail

export UV_NO_CONFIG=1
export UV_OFFLINE=1
export UV_PYTHON_DOWNLOADS=never
export UV_CACHE_DIR="${PWD}/.uv-cache"
export UV_PYTHON_INSTALL_DIR="${PWD}/user-python"
export UV_PYTHON_BIN_DIR="${PWD}/user-bin"
export UV_TOOL_DIR="${PWD}/tools"
export UV_TOOL_BIN_DIR="${PWD}/tool-bin"

# A normal uv Python uninstall must not discover the conda-owned runtime.
uv python uninstall 3.14.8
test "$("${PREFIX}/bin/python" --version)" = 'Python 3.14.8'

"${PREFIX}/bin/python" -I tests/make-wheel.py
uv tool install \
  --python "${PREFIX}/bin/python" \
  --link-mode copy \
  wheels/devkit_python_probe-1.0.0-py3-none-any.whl
test "$("${UV_TOOL_BIN_DIR}/devkit-python-probe")" = 3.14.8
"${UV_TOOL_DIR}/devkit-python-probe/bin/python" -I -c \
  'import os, pathlib, sys; assert pathlib.Path(sys.base_prefix).resolve() == pathlib.Path(os.environ["PREFIX"]) / "lib/uv-python/cpython-3.14.8-linux-x86_64-gnu"'
