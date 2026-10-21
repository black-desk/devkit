#!/usr/bin/env bash
set -euxo pipefail
export UV_NO_CONFIG=1 UV_PYTHON_DOWNLOADS=never
export UV_CACHE_DIR="${SRC_DIR}/.uv-cache"
# The release wheel caps Python below 3.14. Rebuild the source with an explicit
# compatibility declaration, checked by the installed CLI smoke test on 3.14.
sed -i 's/requires-python = ">=3.8.0,<3.14"/requires-python = ">=3.8.0,<3.15"/' tool-source/pyproject.toml
"${BUILD_PREFIX}/bin/uv" venv --python "${PREFIX}/bin/python" "${SRC_DIR}/build-venv"
"${BUILD_PREFIX}/bin/uv" pip install --python "${SRC_DIR}/build-venv/bin/python" \
	--no-build --require-hashes -r "${RECIPE_DIR}/build-requirements.lock"
"${BUILD_PREFIX}/bin/uv" build --offline --wheel --no-build-isolation \
	--python "${SRC_DIR}/build-venv/bin/python" --out-dir "${SRC_DIR}/artifacts" tool-source
# The patched local wheel inherits the pinned sdist's provenance; record its
# actual hash alongside the downloaded dependencies for the final install.
export TOOL_REQUIREMENTS="${SRC_DIR}/requirements.lock"
python3 - <<'LOCK'
import hashlib
import os
from pathlib import Path

wheel = next((Path(os.environ["SRC_DIR"]) / "artifacts").glob("*.whl"))
requirements = (Path(os.environ["RECIPE_DIR"]) / "requirements.lock").read_text()
digest = hashlib.sha256(wheel.read_bytes()).hexdigest()
Path(os.environ["TOOL_REQUIREMENTS"]).write_text(
    requirements + f"cmake-language-server @ {wheel.as_uri()} --hash=sha256:{digest}\n"
)
LOCK
bash "${RECIPE_DIR}/install.sh"
