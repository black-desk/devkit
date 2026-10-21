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
	"${PREFIX}/bin" \
	"${PREFIX}/lib/devkit/share/bash-completion/completions" \
	"${PREFIX}/lib/devkit/share/fish/vendor_completions.d" \
	"${PREFIX}/lib/devkit/share/zsh/site-functions"

go mod download
go mod verify
go build -trimpath -buildvcs=false \
	-ldflags "-s -w -X main.version=${PKG_VERSION} -X main.builtBy=devkit" \
	-o "${PREFIX}/bin/chezmoi" .
"${PREFIX}/bin/chezmoi" completion bash >"${PREFIX}/lib/devkit/share/bash-completion/completions/chezmoi"
"${PREFIX}/bin/chezmoi" completion fish >"${PREFIX}/lib/devkit/share/fish/vendor_completions.d/chezmoi.fish"
"${PREFIX}/bin/chezmoi" completion zsh >"${PREFIX}/lib/devkit/share/zsh/site-functions/_chezmoi"
