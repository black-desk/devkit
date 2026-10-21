#!/usr/bin/env bash
set -euxo pipefail
shfmt --version | grep -F v3.14.1
printf 'if true;then\necho hello\nfi\n' >input.sh
shfmt -i 2 -w input.sh
shfmt -i 2 -d input.sh
grep -Fx '  echo hello' input.sh
# shellcheck disable=SC2016
test "$(gosh -c 'echo $((6 * 7))')" = 42
