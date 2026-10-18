#!/usr/bin/env bash
set -euxo pipefail

: "${SYSROOT_TRIPLET:?}"
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
  COMMON_FLAGS="--no-default-config --config=${BUILD_PREFIX}/lib/devkit/share/devkit/clang.cfg -O2 -fPIC --rtlib=compiler-rt"
fi
COMMON_FLAGS="--start-no-unused-arguments ${COMMON_FLAGS} --end-no-unused-arguments"
CXX_FLAGS="${COMMON_FLAGS}"
if [[ "${SYSROOT_TRIPLET}" == x86_64-conda-linux-gnu ]]; then
  CXX_FLAGS="${CXX_FLAGS} --start-no-unused-arguments -stdlib=libc++ -nostdinc++ -isystem ${PREFIX}/lib/devkit/include/libcxx-23.1.3/c++/v1 --end-no-unused-arguments"
fi
LINK_FLAGS="--ld-path=${BUILD_PREFIX}/bin/ld.lld --unwindlib=none -L${PREFIX}/lib/devkit/lib -Wl,-rpath-link,${PREFIX}/lib/devkit/lib -Wl,-rpath-link,${SYSROOT}/lib64 -lgcc_s"

cmake -S "${SRC_DIR}/llvm" -B build -G Ninja \
  -DCMAKE_PREFIX_PATH="${PREFIX}/lib/devkit" \
  -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=OFF \
  '-DCMAKE_INSTALL_RPATH=$ORIGIN:$ORIGIN/../lib/devkit/lib' \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_INSTALL_DATAROOTDIR=lib/devkit/share \
  -DCMAKE_INSTALL_LIBEXECDIR=lib/devkit/libexec \
  -DCMAKE_INSTALL_LIBDIR=lib/devkit/lib \
  -DCMAKE_INSTALL_INCLUDEDIR=lib/devkit/include \
  -DCMAKE_INSTALL_PACKAGEDIR=lib/devkit/lib/cmake \
  -DCMAKE_BUILD_RPATH="${PREFIX}/lib/devkit/lib" \
  -DCMAKE_C_COMPILER="${CC}" \
  -DCMAKE_CXX_COMPILER="${CXX}" \
  -DCMAKE_ASM_COMPILER="${CC}" \
  -DCMAKE_AR="${BUILD_PREFIX}/bin/llvm-ar" \
  -DCMAKE_RANLIB="${BUILD_PREFIX}/bin/llvm-ranlib" \
  -DCMAKE_C_FLAGS="${COMMON_FLAGS}" \
  -DCMAKE_CXX_FLAGS="${CXX_FLAGS}" \
  -DCMAKE_ASM_FLAGS="${COMMON_FLAGS}" \
  -DCMAKE_EXE_LINKER_FLAGS="${LINK_FLAGS}" \
  -DCMAKE_SHARED_LINKER_FLAGS="${LINK_FLAGS}" \
  -DCMAKE_MODULE_LINKER_FLAGS="${LINK_FLAGS}" \
  -DCMAKE_FIND_ROOT_PATH="${SYSROOT};${PREFIX}" \
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
  -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
  -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY \
  -DLLVM_LIBDIR_SUFFIX=/devkit/lib \
  -DLLVM_ENABLE_PROJECTS="clang;lld" \
  -DLLVM_TARGETS_TO_BUILD=all \
  -DLLVM_BUILD_LLVM_DYLIB=ON \
  -DLLVM_LINK_LLVM_DYLIB=ON \
  -DLLVM_PARALLEL_LINK_JOBS=2 \
  -DLLVM_ENABLE_LIBCXX=ON \
  -DLLVM_INCLUDE_TESTS=OFF \
  -DLLVM_INCLUDE_BENCHMARKS=OFF \
  -DLLVM_INCLUDE_EXAMPLES=OFF \
  -DLLVM_ENABLE_BINDINGS=OFF \
  -DLLVM_ENABLE_ZLIB=FORCE_ON \
  -DZLIB_INCLUDE_DIR="${PREFIX}/lib/devkit/include/zlib-1.3.2" \
  -DZLIB_LIBRARY="${PREFIX}/lib/devkit/lib/libz.so" \
  -DLLVM_ENABLE_ZSTD=FORCE_ON \
  -Dzstd_INCLUDE_DIR="${PREFIX}/lib/devkit/include/zstd-1.5.7" \
  -Dzstd_LIBRARY="${PREFIX}/lib/devkit/lib/libzstd.so" \
  -DLLVM_ENABLE_LIBXML2=FORCE_ON \
  -DLIBXML2_INCLUDE_DIR="${PREFIX}/lib/devkit/include/libxml2-2.15.4/libxml2" \
  -DLIBXML2_LIBRARY="${PREFIX}/lib/devkit/lib/libxml2.so" \
  -DLLVM_ENABLE_RTTI=ON \
  -DLLVM_ENABLE_BACKTRACES=ON \
  -DLLVM_ENABLE_DUMP=ON \
  -DLLVM_USE_INTEL_JITEVENTS=ON \
  -DLLVM_INSTALL_UTILS=ON \
  -DLLVM_ENABLE_LIBEDIT=OFF \
  -DLLVM_ENABLE_TERMINFO=OFF \
  -DCLANG_DEFAULT_PIE_ON_LINUX=ON \
  -DCLANG_DEFAULT_CXX_STDLIB=libstdc++ \
  -DCLANG_DEFAULT_LINKER=/usr/bin/ld

# Use every CPU made available by the build runner. The separate LLVM link
# pool still limits concurrent memory-heavy link tasks to two.
JOBS="${CPU_COUNT}"
cmake --build build --parallel "${JOBS}"
cmake --install build

# Keep the early bootstrap unwinder minimal; user-facing compiler runtimes
# are built here, after channel libc++ is available, without a dependency cycle.
source "${RECIPE_DIR}/build-runtimes.sh"

# Runtime objects are owned by llvm-libgcc, not duplicated in the compiler.
mkdir -p "${PREFIX}/lib/devkit/lib/clang/23/lib"
ln -s ../../../linux "${PREFIX}/lib/devkit/lib/clang/23/lib/linux"

install -d "${PREFIX}/lib/devkit/share/devkit"
install -m 0644 "${RECIPE_DIR}/clang.cfg" "${PREFIX}/lib/devkit/share/devkit/clang.cfg"
install -m 0644 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}/lib/devkit/share/devkit/finalize-elf.py"
for driver in clang clang++; do
  install -m 0644 "${RECIPE_DIR}/host.cfg" "${PREFIX}/bin/${driver}.cfg"
done
