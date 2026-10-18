#!/usr/bin/env bash
set -euxo pipefail

: "${SYSROOT_TRIPLET:?rattler-build must provide sysroot_triplet}"
: "${LIBCXX_VERSION:?rattler-build must provide LIBCXX_VERSION}"
SYSROOT="${BUILD_PREFIX}/${SYSROOT_TRIPLET}/sysroot"
CC="${BUILD_PREFIX}/bin/clang"
CXX="${BUILD_PREFIX}/bin/clang++"
if [[ "${SYSROOT_TRIPLET}" == x86_64-conda-linux-gnu ]]; then
  # Prepare the fresh seed build environment with unversioned driver names.
  ln -sfn clang-23 "${BUILD_PREFIX}/bin/clang"
  ln -sfn clang++-23 "${BUILD_PREFIX}/bin/clang++"
  GCC_INSTALL="${BUILD_PREFIX}/lib/gcc/x86_64-conda-linux-gnu/16.2.0"
  COMMON_FLAGS="--no-default-config --sysroot=${SYSROOT} --gcc-install-dir=${GCC_INSTALL} -O2 -fPIC --rtlib=compiler-rt"
else
  # Building libc++ itself must not inherit clang.cfg's installed libc++
  # include path: C wrapper include_next would select the old wrappers.
  COMMON_FLAGS="--no-default-config --sysroot=${SYSROOT} --gcc-toolchain=${BUILD_PREFIX}/lib/devkit/share/devkit/no-gcc -O2 -fPIC --rtlib=compiler-rt"
fi
COMMON_FLAGS="--start-no-unused-arguments ${COMMON_FLAGS} --end-no-unused-arguments"
LINK_FLAGS="--ld-path=${BUILD_PREFIX}/bin/ld.lld --unwindlib=none -L${PREFIX}/lib/devkit/lib -Wl,-rpath-link,${SYSROOT}/lib64"

cmake -S "${SRC_DIR}/runtimes" -B build -G Ninja \
  -DCMAKE_PREFIX_PATH="${PREFIX}/lib/devkit" \
  -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=OFF \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_INSTALL_DATAROOTDIR=lib/devkit/share \
  -DCMAKE_INSTALL_LIBEXECDIR=lib/devkit/libexec \
  -DCMAKE_INSTALL_LIBDIR=lib/devkit/lib \
  -DCMAKE_BUILD_RPATH="${PREFIX}/lib/devkit/lib" \
  '-DCMAKE_INSTALL_RPATH=$ORIGIN' \
  -DCMAKE_C_COMPILER="${CC}" \
  -DCMAKE_CXX_COMPILER="${CXX}" \
  -DCMAKE_C_COMPILER_TARGET=x86_64-pc-linux-gnu \
  -DCMAKE_CXX_COMPILER_TARGET=x86_64-pc-linux-gnu \
  -DCMAKE_AR="${BUILD_PREFIX}/bin/llvm-ar" \
  -DCMAKE_RANLIB="${BUILD_PREFIX}/bin/llvm-ranlib" \
  -DCMAKE_FIND_ROOT_PATH="${SYSROOT};${PREFIX}" \
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
  -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
  -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY \
  -DCMAKE_C_FLAGS="${COMMON_FLAGS}" \
  -DCMAKE_CXX_FLAGS="${COMMON_FLAGS} -nostdinc++ -nostdlib++" \
  -DCMAKE_EXE_LINKER_FLAGS="${LINK_FLAGS}" \
  -DCMAKE_SHARED_LINKER_FLAGS="${LINK_FLAGS}" \
  -DCMAKE_MODULE_LINKER_FLAGS="${LINK_FLAGS}" \
  -DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi" \
  -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF \
  -DLIBCXX_INSTALL_LIBRARY_DIR=lib/devkit/lib \
  -DLIBCXX_INSTALL_MODULES_DIR=lib/devkit/share/libc++/v1 \
  -DLIBCXXABI_INSTALL_LIBRARY_DIR=lib/devkit/lib \
  -DLIBCXX_INSTALL_INCLUDE_DIR="lib/devkit/include/libcxx-${LIBCXX_VERSION}/c++/v1" \
  -DLIBCXXABI_INSTALL_INCLUDE_DIR="lib/devkit/include/libcxx-${LIBCXX_VERSION}/c++/v1" \
  -DLIBCXX_INCLUDE_TESTS=OFF \
  -DLIBCXXABI_INCLUDE_TESTS=OFF \
  -DLIBCXX_USE_COMPILER_RT=ON \
  -DLIBCXXABI_USE_COMPILER_RT=ON \
  -DLIBCXXABI_USE_LLVM_UNWINDER=OFF \
  -DLIBCXXABI_HAS_GCC_S_LIB=ON

# USE_LLVM_UNWINDER=OFF means use the separately packaged system interface;
# its gcc_s name is supplied by llvm-libgcc, not the GNU implementation.
cmake --build build --parallel "${CPU_COUNT}"
cmake --install build

# Seed tools can load dirty ICU through its public SONAME alias, so its C++
# dependencies need matching aliases until the entire dirty stage is complete.
if [[ "${SYSROOT_TRIPLET}" == x86_64-conda-linux-gnu ]]; then
  for library in libc++.so.1 libc++abi.so.1; do
    ln -sfn "devkit/lib/${library}" "${PREFIX}/lib/${library}"
  done
fi
