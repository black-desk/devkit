#!/usr/bin/env bash
set -euxo pipefail
cmake-format --version | grep -F 0.6.13
printf 'set(FOO a b c)\n' >CMakeLists.txt
cmake-format -i CMakeLists.txt
cmake-format --check CMakeLists.txt
cmake-lint CMakeLists.txt
cmake-annotate CMakeLists.txt >annotated.html
grep -F '<span' annotated.html
"${PREFIX}/lib/devkit/share/devkit/python-tools/cmakelang/bin/python" -I -c 'import yaml, jinja2; assert yaml.safe_load("key: value")["key"] == "value"'
