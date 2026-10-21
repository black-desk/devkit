#!/usr/bin/env bash
set -euxo pipefail
pandoc --version | grep -F 'pandoc 3.12.1'
printf '# Devkit\n\nHello **world**.\n' >sample.md
pandoc -f markdown -t html sample.md -o sample.html
grep -F '<strong>world</strong>' sample.html
pandoc sample.md --pdf-engine=typst -o sample.pdf
head -c 5 sample.pdf | grep -F '%PDF-'
printf 'function Strong(el) return pandoc.Emph(el.content) end\n' >filter.lua
pandoc --lua-filter=filter.lua -f markdown -t html sample.md | grep -F '<em>world</em>'
pandoc sample.md -o sample.docx
pandoc sample.docx -t plain | grep -F 'Hello world.'
pandoc-lua -e 'print(6 * 7)' | grep -Fx 42
