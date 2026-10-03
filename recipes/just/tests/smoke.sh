#!/usr/bin/env bash
set -euxo pipefail

just --justfile tests/justfile --list | grep -F hello
test "$(just --justfile tests/justfile hello package)" = 'devkit package'
test "$(cat tests/prepared.txt)" = ready
just --justfile tests/justfile --dry-run hello dry >dry-run.txt 2>&1
grep -F dry dry-run.txt
for file in \
  share/bash-completion/completions/just \
  share/fish/vendor_completions.d/just.fish \
  share/zsh/site-functions/_just \
  share/man/man1/just.1; do
  test -s "${PREFIX}/${file}"
done
