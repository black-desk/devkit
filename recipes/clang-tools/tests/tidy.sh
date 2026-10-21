#!/usr/bin/env bash
set -euxo pipefail

test "$(command -v clang-tidy)" = "${PREFIX}/bin/clang-tidy"
clang-tidy --version | grep -F '23.1.3'
clang-apply-replacements --version | grep -F '23.1.3'
run-clang-tidy --help >/dev/null
python3 "${PREFIX}/lib/devkit/share/clang/clang-tidy-diff.py" --help >/dev/null

mkdir workspace
cd workspace
cat >sample.cpp <<'CPP'
#include <stddef.h>
int *pointer = 0;
int main() {
    size_t count = 2;
    return pointer == 0 ? static_cast<int>(count) : *pointer;
}
CPP
python3 - <<'PY'
import json
import os
from pathlib import Path

root = Path.cwd()
commands = [{
    "directory": str(root),
    "file": str(root / "sample.cpp"),
    "arguments": [os.environ["PREFIX"] + "/bin/clang++", "-std=c++17",
                  "-fsyntax-only", str(root / "sample.cpp")],
}]
Path("compile_commands.json").write_text(json.dumps(commands))
PY
if clang-tidy -p . --checks='-*,modernize-use-nullptr' \
	--warnings-as-errors=modernize-use-nullptr sample.cpp >diagnostics.log 2>&1; then
	exit 1
fi
grep -F '[modernize-use-nullptr' diagnostics.log
clang-tidy -p . --checks='-*,modernize-use-nullptr' --fix sample.cpp
grep -F 'int *pointer = nullptr;' sample.cpp
run-clang-tidy -p . -j 2 -checks='-*,modernize-use-nullptr' \
	-warnings-as-errors=modernize-use-nullptr sample.cpp

cat >broken.cpp <<'CPP'
int main() {
    int *pointer = nullptr;
    return *pointer;
}
CPP
if clang-tidy --checks='-*,clang-analyzer-core.NullDereference' \
	--warnings-as-errors=clang-analyzer-core.NullDereference broken.cpp \
	-- -std=c++17 >analyzer.log 2>&1; then
	exit 1
fi
grep -F '[clang-analyzer-core.NullDereference' analyzer.log

# Exercise exported fixes and the companion tool without editing the source first.
printf 'int *replacement = 0;\n' >replacement.cpp
clang-tidy --checks='-*,modernize-use-nullptr' --export-fixes=fixes.yaml \
	replacement.cpp -- -std=c++17
clang-apply-replacements .
grep -F 'int *replacement = nullptr;' replacement.cpp
