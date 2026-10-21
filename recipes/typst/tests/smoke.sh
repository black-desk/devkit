#!/usr/bin/env bash
set -euxo pipefail

export XDG_CACHE_HOME="${PWD}/cache"
export XDG_DATA_HOME="${PWD}/data"
export TYPST_PACKAGE_PATH="${PREFIX}/lib/devkit/share/typst/packages"
export TYPST_FONT_PATHS="${PREFIX}/lib/devkit/share/fonts"

test "$(command -v typst)" = "${PREFIX}/bin/typst"
grep -F "\"TYPST_PACKAGE_PATH\": \"${TYPST_PACKAGE_PATH}\"" "${PREFIX}/etc/conda/env_vars.d/typst.json"
grep -F "\"TYPST_FONT_PATHS\": \"${TYPST_FONT_PATHS}\"" "${PREFIX}/etc/conda/env_vars.d/typst.json"
typst info >info.txt 2>&1
grep -F "${TYPST_PACKAGE_PATH}" info.txt
grep -F "${TYPST_FONT_PATHS}" info.txt
typst fonts --ignore-system-fonts | grep -F 'Libertinus Serif'
typst compile --ignore-system-fonts tests/document.typ document.pdf
test "$(head -c 5 document.pdf)" = '%PDF-'
typst compile --ignore-system-fonts tests/document.typ document.svg
grep -F '<svg' document.svg
typst compile --ignore-system-fonts tests/document.typ document.png
test -s document.png
typst compile --features html --format html tests/document.typ document.html
grep -F 'devkit typesetting' document.html
typst query --ignore-system-fonts tests/document.typ '<probe>' >query.json
grep -F 'devkit typesetting' query.json

for file in \
	lib/devkit/share/bash-completion/completions/typst \
	lib/devkit/share/fish/vendor_completions.d/typst.fish \
	lib/devkit/share/zsh/site-functions/_typst \
	lib/devkit/share/man/man1/typst.1 \
	etc/conda/env_vars.d/typst.json; do
	test -s "${PREFIX}/${file}"
done
