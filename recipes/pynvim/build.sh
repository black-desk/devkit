#!/usr/bin/env bash
set -euxo pipefail

export PATH="${BUILD_PREFIX}/bin:${PATH}"
export CC="${BUILD_PREFIX}/bin/clang"
export CXX="${BUILD_PREFIX}/bin/clang++"
export AR="${BUILD_PREFIX}/bin/llvm-ar"
export RANLIB="${BUILD_PREFIX}/bin/llvm-ranlib"
DEVKIT_FLAGS="--no-default-config --config=${BUILD_PREFIX}/lib/devkit/share/devkit/clang.cfg"
export CFLAGS="${DEVKIT_FLAGS} -O2 -fPIC"
export CXXFLAGS="${CFLAGS}"
export LDFLAGS="${DEVKIT_FLAGS} -L${PREFIX}/lib/devkit/lib -Wl,-rpath-link,${PREFIX}/lib/devkit/lib"

export UV_NO_CONFIG=1 UV_OFFLINE=1 UV_PYTHON_DOWNLOADS=never
export UV_CACHE_DIR="${SRC_DIR}/.uv-cache"
export UV_TOOL_DIR="${PREFIX}/lib/devkit/share/devkit/python-tools"
export UV_TOOL_BIN_DIR="${PREFIX}/bin"
uv venv --python "${PREFIX}/bin/python" "${SRC_DIR}/build-venv"
uv pip install --python "${SRC_DIR}/build-venv/bin/python" \
	--no-index --find-links "${SRC_DIR}/artifacts" \
	--constraints "${RECIPE_DIR}/requirements.lock" setuptools
for source in greenlet-3.5.6 msgpack-1.2.3; do
	uv build --wheel --no-build-isolation \
		--python "${SRC_DIR}/build-venv/bin/python" \
		--out-dir "${SRC_DIR}/artifacts" "${SRC_DIR}/artifacts/${source}.tar.gz"
done
uv tool install --python "${PREFIX}/bin/python" --link-mode copy \
	--no-index --find-links "${SRC_DIR}/artifacts" --no-build \
	--constraints "${RECIPE_DIR}/requirements.lock" "pynvim==${PKG_VERSION}"
ln -sfn ../lib/devkit/share/devkit/python-tools/pynvim/bin/pynvim-python "${PREFIX}/bin/pynvim-python"
rm -f "${UV_TOOL_DIR}/.lock" "${UV_TOOL_DIR}/.gitignore"

# Setuptools wheels contain extensions at different depths (including greenlet's
# test modules). Finalize their installed RUNPATH after uv lays out the wheels.
"${BUILD_PREFIX}/bin/python" - <<'PYTHON'
import os
from pathlib import Path
import subprocess

prefix = Path(os.environ['PREFIX'])
tool = prefix / 'lib/devkit/share/devkit/python-tools/pynvim'
for extension in tool.rglob('*.so'):
    relative = os.path.relpath(prefix / 'lib/devkit/lib', extension.parent)
    subprocess.run(
        ['patchelf', '--set-rpath', '$ORIGIN/' + relative, str(extension)],
        check=True,
    )
PYTHON

mkdir -p "${SRC_DIR}/licenses"
for metadata in "${UV_TOOL_DIR}/pynvim/lib/python3.14/site-packages/"*.dist-info; do
	destination="${SRC_DIR}/licenses/$(basename "$metadata")"
	mkdir -p "$destination"
	(
		cd "$metadata"
		find . -type f \( -iname '*license*' -o -iname '*copying*' -o -iname '*notice*' \) \
			-exec cp --parents '{}' "$destination" \;
	)
done
