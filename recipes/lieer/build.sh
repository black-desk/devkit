#!/usr/bin/env bash
set -euxo pipefail

export PATH="${BUILD_PREFIX}/bin:${PATH}"
export CC="${BUILD_PREFIX}/bin/clang"
export CXX="${BUILD_PREFIX}/bin/clang++"
export AR="${BUILD_PREFIX}/bin/llvm-ar"
export RANLIB="${BUILD_PREFIX}/bin/llvm-ranlib"
export NM="${BUILD_PREFIX}/bin/llvm-nm"
export STRIP="${BUILD_PREFIX}/bin/llvm-strip"
export CFLAGS="--no-default-config --config=${BUILD_PREFIX}/lib/devkit/share/devkit/clang.cfg -O2 -fPIC"
export CXXFLAGS="${CFLAGS}"
export CPPFLAGS=""
export LDFLAGS="--no-default-config --config=${BUILD_PREFIX}/lib/devkit/share/devkit/clang.cfg -L${PREFIX}/lib/devkit/lib -Wl,-rpath-link,${PREFIX}/lib/devkit/lib -Wl,--enable-new-dtags,-rpath,${PREFIX}/lib/devkit/lib"
export PKG_CONFIG="${BUILD_PREFIX}/bin/pkg-config"
export PKG_CONFIG_LIBDIR="${PREFIX}/lib/devkit/lib/pkgconfig"
export PKG_CONFIG_PATH="${PKG_CONFIG_LIBDIR}"

export UV_NO_CONFIG=1 UV_OFFLINE=1 UV_PYTHON_DOWNLOADS=never
export UV_CACHE_DIR="${SRC_DIR}/.uv-cache"
export UV_TOOL_DIR="${PREFIX}/lib/devkit/share/devkit/python-tools"
export UV_TOOL_BIN_DIR="${PREFIX}/bin"
uv venv --python "${PREFIX}/bin/python" "${SRC_DIR}/build-venv"
uv pip install --python "${SRC_DIR}/build-venv/bin/python" \
  --no-index --find-links "${SRC_DIR}/artifacts" \
  --constraints "${RECIPE_DIR}/requirements.lock" setuptools wheel cffi
# Build the bindings from the same pinned notmuch release as the channel C API.
cat >bindings/python-cffi/_notmuch_config.py <<EOF
NOTMUCH_VERSION_FILE='${SRC_DIR}/version.txt'
NOTMUCH_INCLUDE_DIR='${PREFIX}/lib/devkit/include/notmuch-0.39'
NOTMUCH_LIB_DIR='${PREFIX}/lib/devkit/lib'
EOF
uv build --wheel --no-build-isolation --python "${SRC_DIR}/build-venv/bin/python" \
  --out-dir "${SRC_DIR}/artifacts" bindings/python-cffi
uv build --wheel --no-build-isolation --python "${SRC_DIR}/build-venv/bin/python" \
  --out-dir "${SRC_DIR}/artifacts" "${SRC_DIR}/artifacts/lieer-${PKG_VERSION}.tar.gz"
uv tool install --python "${PREFIX}/bin/python" --link-mode copy \
  --no-index --find-links "${SRC_DIR}/artifacts" --no-build \
  --constraints "${RECIPE_DIR}/requirements.lock" "lieer==${PKG_VERSION}"
ln -sfn ../lib/devkit/share/devkit/python-tools/lieer/bin/gmi "${PREFIX}/bin/gmi"
rm -f "${UV_TOOL_DIR}/.lock" "${UV_TOOL_DIR}/.gitignore"
# Only the source-built binding needs a channel RUNPATH. Imported manylinux
# extensions preserve their vendor RPATHs and bundled library directories.
python3 - <<'PYTHON'
import os
from pathlib import Path
import subprocess
prefix = Path(os.environ['PREFIX'])
for extension in (prefix / 'lib/devkit/share/devkit/python-tools/lieer').rglob('_capi*.so'):
    relative = os.path.relpath(prefix / 'lib/devkit/lib', extension.parent)
    subprocess.run(['patchelf', '--set-rpath', '$ORIGIN/' + relative, str(extension)], check=True)
PYTHON
mkdir -p "${SRC_DIR}/licenses"
for metadata in "${UV_TOOL_DIR}/lieer/lib/python3.14/site-packages/"*.dist-info; do
  destination="${SRC_DIR}/licenses/$(basename "$metadata")"
  mkdir -p "$destination"
  (
    cd "$metadata"
    find . -type f \( -iname '*license*' -o -iname '*copying*' -o -iname '*notice*' \) \
      -exec cp --parents '{}' "$destination" \;
  )
done
cp COPYING-GPL-3 "${SRC_DIR}/licenses/notmuch-COPYING-GPL-3"
