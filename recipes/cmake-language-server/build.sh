#!/usr/bin/env bash
set -euxo pipefail
export UV_NO_CONFIG=1 UV_OFFLINE=1 UV_PYTHON_DOWNLOADS=never
export UV_CACHE_DIR="${SRC_DIR}/.uv-cache"
# The release wheel caps Python below 3.14. Rebuild the source with an explicit
# compatibility declaration, checked by installed LSP/formatting tests on 3.14.
sed -i 's/requires-python = ">=3.8.0,<3.14"/requires-python = ">=3.8.0,<3.15"/' tool-source/pyproject.toml
"${BUILD_PREFIX}/bin/uv" venv --python "${PREFIX}/bin/python" "${SRC_DIR}/build-venv"
"${BUILD_PREFIX}/bin/uv" pip install --python "${SRC_DIR}/build-venv/bin/python" \
	--no-index --find-links "${SRC_DIR}/artifacts" --no-build pdm-backend==2.5.0
"${BUILD_PREFIX}/bin/uv" build --wheel --no-build-isolation \
	--python "${SRC_DIR}/build-venv/bin/python" --out-dir "${SRC_DIR}/artifacts" tool-source
bash "${RECIPE_DIR}/install.sh"
