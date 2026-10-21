#!/usr/bin/env bash
set -euxo pipefail

export GOPATH="${SRC_DIR}/.go-path"
export GOMODCACHE="${SRC_DIR}/.go-mod-cache"
export GOCACHE="${SRC_DIR}/.go-build-cache"
export GOTMPDIR="${SRC_DIR}/.go-tmp"
export GOENV=off
export GOWORK=off
export GOTOOLCHAIN=local
export GOTELEMETRY=off
# Match the no-cgo baseline: this application needs no C/C++ runtime linkage.
export CGO_ENABLED=0
export GOFLAGS="-mod=readonly"

mkdir -p "${GOPATH}" "${GOMODCACHE}" "${GOCACHE}" "${GOTMPDIR}" "${PREFIX}/bin"
test -x "${BUILD_PREFIX}/bin/go"
# Source archives have no module release metadata; stamp the pinned version
# while retaining upstream's version reporting for installed Go modules.
sed -i "s/version := \"(unknown)\"/version := \"v${PKG_VERSION}\"/" cmd/shfmt/main.go
sed -i 's/version = mod.Version/if mod.Version != "(devel)" { version = mod.Version }/' cmd/shfmt/main.go
"${BUILD_PREFIX}/bin/go" mod download
"${BUILD_PREFIX}/bin/go" mod verify
"${BUILD_PREFIX}/bin/go" build -p 2 -trimpath -buildvcs=false \
	-ldflags "-s -w" \
	-o "${PREFIX}/bin/shfmt" ./cmd/shfmt
"${BUILD_PREFIX}/bin/go" build -p 2 -trimpath -buildvcs=false \
	-ldflags "-s -w" \
	-o "${PREFIX}/bin/gosh" ./cmd/gosh
mkdir -p "${PREFIX}/lib/devkit/share/man/man1"
scdoc <cmd/shfmt/shfmt.1.scd >"${PREFIX}/lib/devkit/share/man/man1/shfmt.1"
