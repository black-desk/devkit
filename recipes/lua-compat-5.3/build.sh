#!/usr/bin/env bash
set -euxo pipefail
mkdir -p "${PREFIX}/lib/devkit/include/lua-compat-5.3-0.13"
cp -R c-api "${PREFIX}/lib/devkit/include/lua-compat-5.3-0.13/"
