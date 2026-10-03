#!/usr/bin/env bash
set -euxo pipefail

: "${PYTHON_VERSION:?rattler-build must provide PYTHON_VERSION}"
: "${PYTHON_MINOR:?rattler-build must provide PYTHON_MINOR}"
: "${PYTHON_INSTALL_KEY:?rattler-build must provide PYTHON_INSTALL_KEY}"
: "${PYTHON_STANDALONE_BUILD:?rattler-build must provide PYTHON_STANDALONE_BUILD}"

test -x "${BUILD_PREFIX}/bin/uv"
export UV_NO_CONFIG=1
export UV_OFFLINE=1
export UV_CACHE_DIR="${SRC_DIR}/.uv-cache"
export UV_PYTHON_INSTALL_DIR="${PREFIX}/lib/uv-python"
export UV_PYTHON_BIN_DIR="${PREFIX}/bin"
export UV_PYTHON_CPYTHON_BUILD="${PYTHON_STANDALONE_BUILD}"
# Rattler-Build verifies and caches the release archive before the build. uv
# reads that archive as a local mirror, retaining its own checksum verification.
export UV_PYTHON_INSTALL_MIRROR="file://${SRC_DIR}"

"${BUILD_PREFIX}/bin/uv" python install "${PYTHON_INSTALL_KEY}" \
  --default \
  --preview-features python-install-default

python_root="${UV_PYTHON_INSTALL_DIR}/${PYTHON_INSTALL_KEY}"
test "$("${PREFIX}/bin/python" --version)" = "Python ${PYTHON_VERSION}"
test "$(cat "${python_root}/BUILD")" = "${PYTHON_STANDALONE_BUILD}"
cp "${python_root}/lib/python${PYTHON_MINOR}/LICENSE.txt" "${SRC_DIR}/LICENSE.txt"

# Conda owns this installation. Keep the PEP 668 protection while identifying
# the actual package manager; user tools and projects belong in virtualenvs.
cat >"${python_root}/lib/python${PYTHON_MINOR}/EXTERNALLY-MANAGED" <<'MARKER'
[externally-managed]
Error=This Python installation is managed by the devkit conda channel. Use conda to update Python and a virtual environment to install Python packages.
MARKER

# Shared manager bookkeeping is build-local state, not part of the runtime.
rm -f "${UV_PYTHON_INSTALL_DIR}/.lock" "${UV_PYTHON_INSTALL_DIR}/.gitignore"
