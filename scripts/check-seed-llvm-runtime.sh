#!/usr/bin/env bash
# Verify upstream seed tools/GNU libstdc++ with the channel LLVM unwinder.
set -euo pipefail
unset LD_LIBRARY_PATH LD_PRELOAD
ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX="$(cd -- "${1:?usage: check-seed-llvm-runtime.sh INSTALL_PREFIX}" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# Bind all dynamic relocations immediately; no loader path/preload overrides.
export LD_BIND_NOW=1
for tool in clang-23 cmake ninja ld.lld llvm-ar llvm-nm llvm-readelf; do
  "$PREFIX/bin/$tool" --version
done
SYSROOT="$PREFIX/x86_64-conda-linux-gnu/sysroot"
GCC_INSTALL="$PREFIX/lib/gcc/x86_64-conda-linux-gnu/16.2.0"
flags="--no-default-config --sysroot=$SYSROOT --gcc-install-dir=$GCC_INSTALL -stdlib=libstdc++ --rtlib=compiler-rt --unwindlib=libgcc"
link_flags="--ld-path=$PREFIX/bin/ld.lld -L$PREFIX/lib -Wl,-rpath,$PREFIX/lib -Wl,-rpath-link,$SYSROOT/lib64"
# TODO: Remove together with the dirty LLVM-libgcc workaround once the six
# GCC_4.3.0 symbol versions required by seed GNU libstdc++ are exported.
link_flags+=" -Wl,--allow-shlib-undefined"

"$PREFIX/bin/cmake" -S "$ROOT/scripts/tests/seed-llvm-runtime" -B "$work/build" -G Ninja \
  -DCMAKE_MAKE_PROGRAM="$PREFIX/bin/ninja" \
  -DCMAKE_CXX_COMPILER="$PREFIX/bin/clang++-23" \
  -DCMAKE_CXX_FLAGS="$flags" -DCMAKE_EXE_LINKER_FLAGS="$link_flags" \
  -DCMAKE_SHARED_LINKER_FLAGS="$link_flags" -DCMAKE_BUILD_RPATH="$PREFIX/lib" \
  -DDEVKIT_PREFIX="$PREFIX"
"$PREFIX/bin/cmake" --build "$work/build"
"$PREFIX/bin/ctest" --test-dir "$work/build" --output-on-failure --verbose
printf 'seed LLVM runtime compatibility probes: OK\n'
