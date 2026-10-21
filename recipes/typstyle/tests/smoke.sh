#!/usr/bin/env bash
set -euxo pipefail
typstyle --version | grep -F 0.15.2
printf '#let x=(1,2,3)\n#x\n' >input.typ
typstyle input.typ >formatted.typ
grep -F '(1, 2, 3)' formatted.typ
typstyle formatted.typ >second.typ
cmp formatted.typ second.typ
typstyle completions bash | grep -F typstyle
