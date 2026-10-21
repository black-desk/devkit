#!/usr/bin/env bash
set -euxo pipefail
unset TYPST_FONT_PATHS TYPST_PACKAGE_PATH TYPST_PACKAGE_CACHE_PATH
export XDG_CACHE_HOME="${PWD}/cache"
tinymist -V | grep -F 0.15.10
printf '= Devkit\n\nHello *world*.\n' >sample.typ
tinymist compile --ignore-system-fonts sample.typ sample.pdf
head -c 5 sample.pdf | grep -F '%PDF-'
python3 tests/lsp.py --document sample.typ --language typst -- tinymist lsp
ldd "${PREFIX}/bin/tinymist" >libraries.txt
if grep -F libstdc++ libraries.txt; then exit 1; fi
