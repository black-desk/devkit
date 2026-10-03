#!/usr/bin/env bash
set -euxo pipefail

export UV_NO_CONFIG=1 UV_OFFLINE=1 UV_PYTHON_DOWNLOADS=never
export UV_CACHE_DIR="${SRC_DIR}/.uv-cache"
export UV_TOOL_DIR="${PREFIX}/share/devkit/python-tools"
export UV_TOOL_BIN_DIR="${PREFIX}/bin"
uv tool install --python "${PREFIX}/bin/python" --link-mode copy \
	--no-index --find-links "${SRC_DIR}/artifacts" "meson==${PKG_VERSION}"
ln -sfn ../share/devkit/python-tools/meson/bin/meson "${PREFIX}/bin/meson"
rm -f "${UV_TOOL_DIR}/.lock" "${UV_TOOL_DIR}/.gitignore"
mkdir -p "${SRC_DIR}/licenses"
cp "${UV_TOOL_DIR}/meson/lib/python3.14/site-packages/meson-${PKG_VERSION}.dist-info/licenses/COPYING" \
	"${SRC_DIR}/licenses/COPYING"
