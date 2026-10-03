#!/usr/bin/env bash
set -euxo pipefail
unset LD_LIBRARY_PATH
test "$(meson --version)" = 1.12.1
test "$(readlink "${PREFIX}/bin/meson")" = ../share/devkit/python-tools/meson/bin/meson
"${PREFIX}/share/devkit/python-tools/meson/bin/python" -I - <<'PY'
import os
import sys
from pathlib import Path
prefix = Path(os.environ['PREFIX'])
assert Path(sys.prefix) == prefix / 'share/devkit/python-tools/meson'
assert Path(sys.base_prefix).is_relative_to(prefix / 'lib/uv-python')
PY
mkdir project
cat >project/meson.build <<'EOF'
project('devkit-smoke', 'c')
executable('probe', 'probe.c')
EOF
cat >project/probe.c <<'EOF'
#include <stdio.h>
int main(void) { puts("devkit"); return 0; }
EOF
CC="${PREFIX}/bin/gcc" meson setup project/build project --wrap-mode=nofallback
meson compile -C project/build
test "$(project/build/probe)" = devkit
