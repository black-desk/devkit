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
export CGO_ENABLED=0
export GOFLAGS="-mod=readonly"

mkdir -p "${GOPATH}" "${GOMODCACHE}" "${GOCACHE}" "${GOTMPDIR}" "${PREFIX}/bin"
test -x "${BUILD_PREFIX}/bin/go"
cd gopls
"${BUILD_PREFIX}/bin/go" mod download
"${BUILD_PREFIX}/bin/go" mod verify
"${BUILD_PREFIX}/bin/go" build \
  -p 2 \
  -trimpath \
  -buildvcs=false \
  -ldflags "-s -w -X main.version=v${PKG_VERSION}" \
  -o "${PREFIX}/bin/gopls" \
  .
