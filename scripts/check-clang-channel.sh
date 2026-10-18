#!/usr/bin/env bash
# Integration check for a prefix containing Clang, runtimes, and local sysroot.
set -euo pipefail
unset LD_LIBRARY_PATH LD_PRELOAD
ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX="$(realpath "${1:?usage: check-clang-channel.sh INSTALL_PREFIX}")"
PROBE_DIR="$(mktemp -d)"
trap 'rm -rf -- "${PROBE_DIR}"' EXIT

"${PREFIX}/bin/clang++" --no-default-config \
  --config="${PREFIX}/lib/devkit/share/devkit/clang.cfg" -std=c++20 \
  "${ROOT}/recipes/libcxx/tests/runtime.cpp" -ldl -pthread \
  "-Wl,-rpath,${PREFIX}/lib/devkit/lib" -o "${PROBE_DIR}/probe"
"${PROBE_DIR}/probe" "${PREFIX}"

"${PREFIX}/bin/clang" --no-default-config \
  --config="${PREFIX}/lib/devkit/share/devkit/clang.cfg" \
  "${ROOT}/recipes/llvm-libgcc/tests/runtime.c" -ldl \
  "-Wl,-rpath,${PREFIX}/lib/devkit/lib" -o "${PROBE_DIR}/probe-c"
"${PROBE_DIR}/probe-c" "${PREFIX}/lib/devkit/lib/libgcc_s.so.1"
