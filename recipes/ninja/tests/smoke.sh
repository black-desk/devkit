#!/usr/bin/env bash
set -euxo pipefail
unset LD_LIBRARY_PATH
test "$(ninja --version)" = 1.13.2
cat >build.ninja <<'EOF'
rule generate
  command = printf 'devkit\n' > $out
build result: generate
EOF
ninja
test "$(cat result)" = devkit
ninja -n | grep -F 'no work to do'
ldd "${PREFIX}/bin/ninja" | grep -F "${PREFIX}/lib/libstdc++.so"
