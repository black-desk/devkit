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
  COMMON_FLAGS="--no-default-config --sysroot=${SYSROOT} --gcc-toolchain=${BUILD_PREFIX}/share/devkit/no-gcc -O2 -fPIC --rtlib=compiler-rt"
fi
COMMON_FLAGS="--start-no-unused-arguments ${COMMON_FLAGS} --end-no-unused-arguments"
LINK_FLAGS="--ld-path=${BUILD_PREFIX}/bin/ld.lld --unwindlib=none -L${PREFIX}/lib/devkit/lib -L${PREFIX}/lib -Wl,-rpath-link,${SYSROOT}/lib64"

cmake -S "${SRC_DIR}/runtimes" -B build -G Ninja \
  -DCMAKE_PREFIX_PATH="${PREFIX}/lib/devkit" \
  -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=OFF \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_BUILD_RPATH="${PREFIX}/lib" \
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

mkdir -p "${PREFIX}/include/libcxx-${LIBCXX_VERSION}"
mv "${PREFIX}/include/c++" "${PREFIX}/include/libcxx-${LIBCXX_VERSION}/c++"
if [[ -d "${PREFIX}/lib/cmake" ]]; then
  while IFS= read -r -d '' metadata; do
    sed -i "s|/include/c++/v1|/include/libcxx-${LIBCXX_VERSION}/c++/v1|g" "${metadata}"
  done < <(find "${PREFIX}/lib/cmake" -type f -name '*.cmake' -print0)
fi
mkdir -p "${PREFIX}/lib/devkit/lib/llvm-runtime"
for library in libc++.so libc++.so.1 libc++.a libc++abi.so libc++abi.so.1 libc++abi.a; do
  ln -s "../${library}" "${PREFIX}/lib/devkit/lib/llvm-runtime/${library}"
done

"${CXX}" ${COMMON_FLAGS} ${LINK_FLAGS} -std=c++20 -nostdinc++ -nostdlib++ \
  -isystem "${PREFIX}/include/libcxx-${LIBCXX_VERSION}/c++/v1" \
  "${RECIPE_DIR}/tests/runtime.cpp" -lc++ -lc++abi -lgcc_s -ldl -pthread \
  '-Wl,--enable-new-dtags,-rpath,$ORIGIN/runtime-lib' \
  -o "${SRC_DIR}/libcxx-probe"

# Stage only this package's development interfaces; preserve runtime libraries.
python3 "${SRC_DIR}/devkit-build/stage-development.py" "${PREFIX}" --all
