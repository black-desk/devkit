#!/usr/bin/env bash
set -euxo pipefail

: "${LAZYGIT_VERSION:?rattler-build must provide LAZYGIT_VERSION}"
: "${LAZYGIT_COMMIT:?rattler-build must provide LAZYGIT_COMMIT}"
: "${LAZYGIT_BUILD_DATE:?rattler-build must provide LAZYGIT_BUILD_DATE}"

test -f vendor/modules.txt
test -x "${BUILD_PREFIX}/bin/go"

export GOPATH="${SRC_DIR}/.go-path"
export GOMODCACHE="${SRC_DIR}/.go-mod-cache"
export GOCACHE="${SRC_DIR}/.go-build-cache"
export GOTMPDIR="${SRC_DIR}/.go-tmp"
export GOENV=off
export GOWORK=off
export GOTOOLCHAIN=local
export CGO_ENABLED=0

mkdir -p "${GOPATH}" "${GOMODCACHE}" "${GOCACHE}" "${GOTMPDIR}" "${PREFIX}/bin"

go build \
  -mod=vendor \
  -trimpath \
  -buildvcs=false \
  -ldflags "\
    -s -w \
    -X main.version=${LAZYGIT_VERSION} \
    -X main.commit=${LAZYGIT_COMMIT} \
    -X main.date=${LAZYGIT_BUILD_DATE} \
    -X main.buildSource=devkit" \
  -o "${PREFIX}/bin/lazygit" \
  .
