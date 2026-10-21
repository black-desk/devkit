#!/usr/bin/env bash
set -euxo pipefail

: "${TOOL_DISTRIBUTION:?}"
: "${TOOL_COMMANDS:?}"
export UV_NO_CONFIG=1 UV_OFFLINE=1 UV_PYTHON_DOWNLOADS=never
export UV_CACHE_DIR="${SRC_DIR}/.uv-cache"
export UV_TOOL_DIR="${PREFIX}/lib/devkit/share/devkit/python-tools"
export UV_TOOL_BIN_DIR="${PREFIX}/bin"
"${BUILD_PREFIX}/bin/uv" tool install \
	--python "${PREFIX}/bin/python" --link-mode copy \
	--no-index --find-links "${SRC_DIR}/artifacts" --no-build \
	--with-requirements "${RECIPE_DIR}/requirements.lock" \
	"${TOOL_DISTRIBUTION}==${PKG_VERSION}"
"${BUILD_PREFIX}/bin/uv" pip check --python "${UV_TOOL_DIR}/${TOOL_DISTRIBUTION}/bin/python"
for command in ${TOOL_COMMANDS}; do
	ln -sfn "../lib/devkit/share/devkit/python-tools/${TOOL_DISTRIBUTION}/bin/${command}" \
		"${PREFIX}/bin/${command}"
done
rm -f "${UV_TOOL_DIR}/.lock" "${UV_TOOL_DIR}/.gitignore"
mkdir -p "${SRC_DIR}/licenses"
for metadata in "${UV_TOOL_DIR}/${TOOL_DISTRIBUTION}/lib/python3.14/site-packages/"*.dist-info; do
	destination="${SRC_DIR}/licenses/$(basename "$metadata")"
	mkdir -p "$destination"
	(
		cd "$metadata"
		find . -type f \( -iname '*license*' -o -iname '*copying*' -o -iname '*notice*' \) \
			-exec cp --parents '{}' "$destination" \;
	)
done
