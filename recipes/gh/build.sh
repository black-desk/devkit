#!/usr/bin/env bash
set -euxo pipefail

export GOPATH="${SRC_DIR}/.go-path"
export GOMODCACHE="${SRC_DIR}/.go-mod-cache"
export GOCACHE="${SRC_DIR}/.go-build-cache"
export GOTMPDIR="${SRC_DIR}/.go-tmp"
export GOENV=off GOWORK=off GOTOOLCHAIN=local GOTELEMETRY=off
export CGO_ENABLED=0
export GOFLAGS="-mod=readonly"
export PATH="${BUILD_PREFIX}/bin:${PATH}"

mkdir -p "${GOPATH}" "${GOMODCACHE}" "${GOCACHE}" "${GOTMPDIR}" \
	"${PREFIX}/bin" "${PREFIX}/lib/devkit/share/man/man1" \
	"${PREFIX}/lib/devkit/share/bash-completion/completions" \
	"${PREFIX}/lib/devkit/share/fish/vendor_completions.d" \
	"${PREFIX}/lib/devkit/share/zsh/site-functions"

go mod download
go mod verify
go build -trimpath -buildvcs=false \
	-ldflags "-s -w -X github.com/cli/cli/v2/internal/build.Version=${PKG_VERSION}" \
	-o "${PREFIX}/bin/gh" ./cmd/gh
go run ./cmd/gen-docs --man-page --doc-path "${PREFIX}/lib/devkit/share/man/man1/"
"${PREFIX}/bin/gh" completion --shell bash >"${PREFIX}/lib/devkit/share/bash-completion/completions/gh"
"${PREFIX}/bin/gh" completion --shell fish >"${PREFIX}/lib/devkit/share/fish/vendor_completions.d/gh.fish"
"${PREFIX}/bin/gh" completion --shell zsh >"${PREFIX}/lib/devkit/share/zsh/site-functions/_gh"
