#!/usr/bin/env bash
set -euxo pipefail

export UV_NO_CONFIG=1
export UV_OFFLINE=1
export UV_PYTHON_DOWNLOADS=never
export UV_CACHE_DIR="${SRC_DIR}/.uv-cache"
export UV_TOOL_DIR="${PREFIX}/share/devkit/python-tools"
export UV_TOOL_BIN_DIR="${PREFIX}/bin"

"${BUILD_PREFIX}/bin/uv" tool install \
  --python "${PREFIX}/bin/python" \
  --python-platform x86_64-manylinux_2_28 \
  --link-mode copy \
  --no-index --find-links "${SRC_DIR}/artifacts" \
  --constraints "${RECIPE_DIR}/requirements.lock" \
  --build-constraints "${RECIPE_DIR}/build-constraints.txt" \
  "b4==${PKG_VERSION}"

# Keep all dependency license notices both in the environment and package info.
mkdir -p "${SRC_DIR}/licenses"
for metadata in "${UV_TOOL_DIR}/b4/lib/python3.14/site-packages/"*.dist-info; do
  destination="${SRC_DIR}/licenses/$(basename "$metadata")"
  mkdir -p "$destination"
  (
    cd "$metadata"
    find . -type f \( -iname '*license*' -o -iname '*copying*' -o -iname '*notice*' \) \
      -exec cp --parents '{}' "$destination" \;
  )
done

# A relative public entrypoint survives relocation alongside the environment.
ln -sfn ../share/devkit/python-tools/b4/bin/b4 "${PREFIX}/bin/b4"
rm -f "${UV_TOOL_DIR}/.lock" "${UV_TOOL_DIR}/.gitignore"
