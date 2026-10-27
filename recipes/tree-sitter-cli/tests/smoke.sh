#!/usr/bin/env bash
set -euxo pipefail

unset LD_LIBRARY_PATH LD_PRELOAD TREE_SITTER_JS_RUNTIME
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
export HOME="${work}/home"
export XDG_CACHE_HOME="${work}/cache"
export XDG_CONFIG_HOME="${work}/config"
mkdir -p "${HOME}" "${work}/grammar"
cd "${work}/grammar"

cat >grammar.js <<'JS'
module.exports = grammar({
  name: 'devkit_smoke',
  rules: {
    source_file: $ => repeat($.word),
    word: $ => /[a-z]+/,
  },
});
JS
cat >tree-sitter.json <<'JSON'
{
  "grammars": [{
    "name": "devkit_smoke",
    "camelcase": "DevkitSmoke",
    "scope": "source.devkit_smoke",
    "path": ".",
    "file-types": ["devkit_smoke"]
  }],
  "metadata": {"version": "0.1.0", "license": "MIT"}
}
JSON

# Exercise grammar.js with the embedded engine and compile the generated C
# with normal user compiler behavior (host development files).
export CC="${PREFIX}/bin/clang"
tree-sitter generate --js-runtime native
test -s src/parser.c
test -s src/node-types.json
tree-sitter build
printf 'hello world\n' >sample.devkit_smoke
tree-sitter parse sample.devkit_smoke >parse.txt
grep -F '(source_file' parse.txt
grep -F '(word' parse.txt
if grep -E 'ERROR|MISSING' parse.txt; then
  exit 1
fi
