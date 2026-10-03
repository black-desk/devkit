#!/usr/bin/env bash
set -euxo pipefail

export GOPATH="${PWD}/go-path"
export GOMODCACHE="${PWD}/go-mod-cache"
export GOCACHE="${PWD}/go-build-cache"
export XDG_CACHE_HOME="${PWD}/cache"
export XDG_CONFIG_HOME="${PWD}/config"
export GOENV=off
export GOWORK=off
export GOTOOLCHAIN=local
export GOTELEMETRY=off
export GOPROXY=off
export GOSUMDB=off
export CGO_ENABLED=0

test "$(gopls version)" = "golang.org/x/tools/gopls v0.23.0"
test "$(command -v go)" = "${PREFIX}/bin/go"
mkdir workspace
cd workspace
printf 'module example.invalid/devkit\n\ngo 1.27.0\n' >go.mod
cat >main.go <<'GO'
package main

func greeting() string { return "hello" }
func main() { println(greeting()) }
GO

gopls check main.go >diagnostics.txt
test ! -s diagnostics.txt
gopls definition main.go:4:23 >definition.txt
grep -F 'main.go:3:' definition.txt
printf '\nvar broken int = "not an integer"\n' >>main.go
gopls check main.go >diagnostics.txt
grep -F 'cannot use' diagnostics.txt
