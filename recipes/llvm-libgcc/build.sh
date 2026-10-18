#!/usr/bin/env bash
set -euxo pipefail

: "${SYSROOT_TRIPLET:?rattler-build must provide sysroot_triplet}"
SYSROOT="${BUILD_PREFIX}/${SYSROOT_TRIPLET}/sysroot"
test -d "${SYSROOT}"

export CC="${BUILD_PREFIX}/bin/clang"
export CXX="${BUILD_PREFIX}/bin/clang++"
if [[ "${SYSROOT_TRIPLET}" == x86_64-conda-linux-gnu ]]; then
  # Prepare the fresh seed build environment with unversioned driver names.
  ln -sfn clang-23 "${BUILD_PREFIX}/bin/clang"
  ln -sfn clang++-23 "${BUILD_PREFIX}/bin/clang++"
  GCC_INSTALL="${BUILD_PREFIX}/lib/gcc/x86_64-conda-linux-gnu/16.2.0"
  test -d "${GCC_INSTALL}"
  COMMON_FLAGS="--no-default-config --sysroot=${SYSROOT} --gcc-install-dir=${GCC_INSTALL} -O2 -fPIC"
else
  COMMON_FLAGS="--no-default-config --config=${BUILD_PREFIX}/share/devkit/clang.cfg -O2 -fPIC"
fi
test -x "${CC}"
test -x "${CXX}"

LINKER="${BUILD_PREFIX}/bin/ld.lld"
test -x "${LINKER}"
LINK_FLAGS="--ld-path=${LINKER} --rtlib=compiler-rt --unwindlib=none -Wl,-rpath-link,${SYSROOT}/lib64"
if [[ "${SYSROOT_TRIPLET}" == x86_64-conda-linux-gnu ]]; then
  # TODO: Remove once LLVM-libgcc exports the GCC_4.3.0 versions of __eqtf2,
  # __getf2, __letf2, __unordtf2, __extendxftf2 and __trunctfxf2. Seed GNU
  # libstdc++ references these versions; LLVM currently exports the functions
  # unversioned. glibc's fallback resolves them, but LLD rejects the shared
  # library references. Limit the relaxation to this GNU-libstdc++ bootstrap;
  # result/self-host builds and normal libc++ recipes keep the strict check.
  LINK_FLAGS+=" -Wl,--allow-shlib-undefined"
fi

cmake -S "${SRC_DIR}/llvm-libgcc" -B build -G Ninja \
  -DCMAKE_PREFIX_PATH="${PREFIX}/lib/devkit" \
  -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=OFF \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_BUILD_RPATH="${PREFIX}/lib" \
  -DCMAKE_INSTALL_RPATH='$ORIGIN' \
  -DCMAKE_C_COMPILER="${CC}" \
  -DCMAKE_CXX_COMPILER="${CXX}" \
  -DCMAKE_ASM_COMPILER="${CC}" \
  -DCMAKE_AR="${BUILD_PREFIX}/bin/llvm-ar" \
  -DCMAKE_RANLIB="${BUILD_PREFIX}/bin/llvm-ranlib" \
  -DCMAKE_NM="${BUILD_PREFIX}/bin/llvm-nm" \
  -DCMAKE_C_COMPILER_TARGET=x86_64-pc-linux-gnu \
  -DCMAKE_CXX_COMPILER_TARGET=x86_64-pc-linux-gnu \
  -DCMAKE_ASM_COMPILER_TARGET=x86_64-pc-linux-gnu \
  -DCMAKE_FIND_ROOT_PATH="${SYSROOT};${BUILD_PREFIX}" \
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
  -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
  -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY \
  -DCMAKE_C_FLAGS="${COMMON_FLAGS}" \
  -DCMAKE_CXX_FLAGS="${COMMON_FLAGS}" \
  -DCMAKE_ASM_FLAGS="${COMMON_FLAGS}" \
  -DCMAKE_EXE_LINKER_FLAGS="${LINK_FLAGS}" \
  -DCMAKE_SHARED_LINKER_FLAGS="${LINK_FLAGS}" \
  -DCMAKE_MODULE_LINKER_FLAGS="${LINK_FLAGS}" \
  -DLLVM_LIBGCC_EXPLICIT_OPT_IN=Yes \
  -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF \
  -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON \
  -DCOMPILER_RT_BUILD_SANITIZERS=OFF \
  -DCOMPILER_RT_BUILD_XRAY=OFF \
  -DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
  -DCOMPILER_RT_BUILD_PROFILE=OFF \
  -DCOMPILER_RT_BUILD_ORC=OFF \
  -DCOMPILER_RT_INCLUDE_TESTS=OFF \
  -DLIBUNWIND_INSTALL_INCLUDE_DIR="lib/devkit/include/libunwind-23.1.3" \
  -DLIBUNWIND_INCLUDE_TESTS=OFF

cmake --build build --target llvm-libgcc crt --parallel "${CPU_COUNT}"
cmake --install build --component llvm-libgcc
cmake --install build --component clang_rt.crtbegin-x86_64
cmake --install build --component clang_rt.crtend-x86_64
cmake --install build --component unwind-headers
# Keep development layout handling in this recipe until channel coverage is complete.
python3 "${RECIPE_DIR}/relocate-development.py"
