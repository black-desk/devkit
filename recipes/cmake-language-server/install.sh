#!/usr/bin/env bash
set -euxo pipefail

: "${TOOL_DISTRIBUTION:?}"
: "${TOOL_COMMANDS:?}"
export UV_NO_CONFIG=1 UV_PYTHON_DOWNLOADS=never
export UV_CACHE_DIR="${SRC_DIR}/.uv-cache"
export UV_TOOL_DIR="${PREFIX}/lib/devkit/share/devkit/python-tools"
export UV_TOOL_BIN_DIR="${PREFIX}/bin"
tool_requirements="${TOOL_REQUIREMENTS:-${RECIPE_DIR}/requirements.lock}"
"${BUILD_PREFIX}/bin/uv" tool install \
	--python "${PREFIX}/bin/python" --link-mode copy --no-build \
	--with-requirements "${tool_requirements}" \
	"${TOOL_DISTRIBUTION}==${PKG_VERSION}"
# tool install does not enforce requirements hashes. Reinstall from the same
# uv cache with pip sync to check hashes and retain only the locked payload.
"${BUILD_PREFIX}/bin/uv" pip sync \
	--python "${UV_TOOL_DIR}/${TOOL_DISTRIBUTION}/bin/python" \
	--link-mode copy --no-build --require-hashes --reinstall "${tool_requirements}"
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
