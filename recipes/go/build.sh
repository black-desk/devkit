#!/usr/bin/env bash
set -euxo pipefail

# Rattler-Build normally strips the distribution's top-level `go/` directory.
# Keep the copy logic tolerant of an unstripped archive so the repack
# behavior does not depend on that extraction detail.
source_root="${SRC_DIR}"
if [[ ! -f "${source_root}/go.env" && -f "${source_root}/go/go.env" ]]; then
  source_root="${source_root}/go"
fi

test -x "${source_root}/bin/go"
test -x "${source_root}/bin/gofmt"

mkdir -p "${PREFIX}"
cp -a "${source_root}/." "${PREFIX}/"

# Normalize collision-prone top-level distribution metadata into the package's
# share directory. Keep go.env at the GOROOT root because it is functional Go
# configuration rather than distribution documentation.
metadata_dir="${PREFIX}/share/go"
mkdir -p "${metadata_dir}"
for file in CONTRIBUTING.md LICENSE PATENTS README.md SECURITY.md VERSION codereview.cfg; do
  if [[ -f "${PREFIX}/${file}" ]]; then
    mv "${PREFIX}/${file}" "${metadata_dir}/${file}"
  fi
done

# Rattler-Build places its generated source/build bookkeeping in the work
# directory. Do not turn those files into part of the Go distribution.
rm -f \
  "${PREFIX}/.source_info.json" \
  "${PREFIX}/build_env.sh" \
  "${PREFIX}/conda_build.sh" \
  "${PREFIX}/conda_build.log"
