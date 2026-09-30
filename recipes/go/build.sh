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

: "${GO_VERSION:?rattler-build must provide GO_VERSION}"

goroot="${PREFIX}/lib/go/${GO_VERSION}"
mkdir -p "${goroot}" "${PREFIX}/bin"
cp -a "${source_root}/." "${goroot}/"

# Keep the command-line interface in the conventional bin directory while
# retaining the official GOROOT layout below a versioned package directory.
# Linux resolves the executable to its real target, so the go command discovers
# this versioned GOROOT without embedding or wrapping it.
ln -s "../lib/go/${GO_VERSION}/bin/go" "${PREFIX}/bin/go"
ln -s "../lib/go/${GO_VERSION}/bin/gofmt" "${PREFIX}/bin/gofmt"

# Rattler-Build places its generated source/build bookkeeping in the work
# directory. Do not turn those files into part of the Go distribution.
rm -f \
  "${goroot}/.source_info.json" \
  "${goroot}/build_env.sh" \
  "${goroot}/conda_build.sh" \
  "${goroot}/conda_build.log"
