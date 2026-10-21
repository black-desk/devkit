#!/usr/bin/env bash
set -euxo pipefail
cmake-language-server --help
printf 'cmake_minimum_required(VERSION 3.20)\nproject(devkit NONE)\nset(FOO    a   b c)\n' >CMakeLists.txt
python3 tests/lsp.py --format --document CMakeLists.txt --language cmake -- cmake-language-server
"${PREFIX}/lib/devkit/share/devkit/python-tools/cmake-language-server/bin/python" -I -c 'import importlib.metadata as m; assert m.version("pygls") == "1.3.1"'
