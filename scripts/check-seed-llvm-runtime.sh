#!/usr/bin/env bash
# Verify seed GNU runtimes coexist with the private channel LLVM unwinder.
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

"$PREFIX/bin/cmake" -S "$ROOT/scripts/tests/seed-llvm-runtime" -B "$work/build" -G Ninja \
  -DCMAKE_MAKE_PROGRAM="$PREFIX/bin/ninja" \
  -DCMAKE_CXX_COMPILER="$PREFIX/bin/clang++-23" \
  -DCMAKE_CXX_FLAGS="$flags" -DCMAKE_EXE_LINKER_FLAGS="$link_flags" \
  -DCMAKE_SHARED_LINKER_FLAGS="$link_flags" -DCMAKE_BUILD_RPATH="$PREFIX/lib" \
  -DDEVKIT_PREFIX="$PREFIX"
"$PREFIX/bin/cmake" --build "$work/build"
"$PREFIX/bin/ctest" --test-dir "$work/build" --output-on-failure --verbose
# A separate C process explicitly loads the private LLVM runtime. Identical
# SONAMEs intentionally do not imply per-DSO isolation inside the seed C++ probe.
"$PREFIX/bin/clang-23" --no-default-config --sysroot="$SYSROOT" \
  --gcc-install-dir="$GCC_INSTALL" --rtlib=compiler-rt --unwindlib=none \
  --ld-path="$PREFIX/bin/ld.lld" \
  -isystem "$PREFIX/lib/devkit/include/libunwind-23.1.3" \
  "$ROOT/recipes/llvm-libgcc/tests/runtime.c" -ldl \
  "-Wl,-rpath,$PREFIX/lib/devkit/lib" -o "$work/llvm-probe"
"$work/llvm-probe" "$PREFIX/lib/devkit/lib/libgcc_s.so.1"
"$work/llvm-probe" libunwind.so.1
printf 'seed GNU/private LLVM runtime coexistence probes: OK\n'
