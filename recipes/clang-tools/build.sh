#!/usr/bin/env bash
set -euxo pipefail

export PATH="${BUILD_PREFIX}/bin:${PATH}"
SYSROOT="${BUILD_PREFIX}/x86_64-pc-linux-gnu/sysroot"
COMMON_FLAGS="--no-default-config --config=${BUILD_PREFIX}/lib/devkit/share/devkit/clang.cfg -O2 -fPIC"
# LLVM adds -stdlib=libc++ too; with the config's -nostdinc++, its compile-only
# warning would otherwise make CMake's -Werror capability checks fail.
CXX_FLAGS="${COMMON_FLAGS} -Wno-unused-command-line-argument"
LINK_FLAGS="-L${PREFIX}/lib/devkit/lib -Wl,-rpath-link,${PREFIX}/lib/devkit/lib -Wl,-rpath-link,${SYSROOT}/lib64"

# Use Clang's supported standalone build against the installed channel LLVM.
# This is also how conda-forge attaches clang-tools-extra to standalone Clang.
mv "${SRC_DIR}/clang-tools-extra" "${SRC_DIR}/clang/tools/extra"
cmake -S "${SRC_DIR}/clang" -B build -G Ninja \
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_INSTALL_PREFIX="${PREFIX}" \
	-DCMAKE_PREFIX_PATH="${PREFIX}/lib/devkit" \
	-DCMAKE_INSTALL_DATADIR=lib/devkit/share \
	-DCMAKE_INSTALL_LIBDIR=lib/devkit/lib \
	-DCMAKE_INSTALL_INCLUDEDIR=lib/devkit/include \
	-DCMAKE_INSTALL_RPATH_USE_LINK_PATH=OFF \
	"-DCMAKE_INSTALL_RPATH=\$ORIGIN/../lib/devkit/lib" \
	-DCMAKE_BUILD_RPATH="${PREFIX}/lib/devkit/lib" \
	-DCMAKE_C_COMPILER="${BUILD_PREFIX}/bin/clang" \
	-DCMAKE_CXX_COMPILER="${BUILD_PREFIX}/bin/clang++" \
	-DCMAKE_ASM_COMPILER="${BUILD_PREFIX}/bin/clang" \
	-DCMAKE_AR="${BUILD_PREFIX}/bin/llvm-ar" \
	-DCMAKE_RANLIB="${BUILD_PREFIX}/bin/llvm-ranlib" \
	-DCMAKE_C_FLAGS="${COMMON_FLAGS}" \
	-DCMAKE_CXX_FLAGS="${CXX_FLAGS}" \
	-DCMAKE_EXE_LINKER_FLAGS="${LINK_FLAGS}" \
	-DCMAKE_SHARED_LINKER_FLAGS="${LINK_FLAGS}" \
	-DCMAKE_MODULE_LINKER_FLAGS="${LINK_FLAGS}" \
	-DCMAKE_FIND_ROOT_PATH="${SYSROOT};${PREFIX}" \
	-DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
	-DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
	-DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY \
	-DLLVM_DIR="${PREFIX}/lib/devkit/lib/cmake/llvm" \
	-DLLVM_LIBDIR_SUFFIX=/devkit/lib \
	-DLLVM_LINK_LLVM_DYLIB=ON \
	-DLLVM_ENABLE_LIBCXX=ON \
	-DLLVM_PARALLEL_LINK_JOBS=2 \
	-DLLVM_INCLUDE_TESTS=OFF \
	-DLLVM_INCLUDE_BENCHMARKS=OFF \
	-DZLIB_INCLUDE_DIR="${PREFIX}/lib/devkit/include/zlib-1.3.2" \
	-DZLIB_LIBRARY="${PREFIX}/lib/devkit/lib/libz.so" \
	-Dzstd_INCLUDE_DIR="${PREFIX}/lib/devkit/include/zstd-1.5.7" \
	-Dzstd_LIBRARY="${PREFIX}/lib/devkit/lib/libzstd.so" \
	-DLIBXML2_INCLUDE_DIR="${PREFIX}/lib/devkit/include/libxml2-2.15.4/libxml2" \
	-DLIBXML2_LIBRARY="${PREFIX}/lib/devkit/lib/libxml2.so" \
	-DCLANG_INCLUDE_TESTS=OFF \
	-DCLANG_INCLUDE_DOCS=OFF \
	-DCLANG_LINK_CLANG_DYLIB=ON \
	-DCLANG_ENABLE_CLANGD=ON \
	-DCLANGD_TIDY_CHECKS=ON \
	-DCLANG_TIDY_ENABLE_STATIC_ANALYZER=ON \
	-DCLANG_TIDY_ENABLE_QUERY_BASED_CUSTOM_CHECKS=ON \
	-DCLANG_DEFAULT_PIE_ON_LINUX=ON \
	-DCLANG_DEFAULT_CXX_STDLIB=libstdc++ \
	-DCLANG_DEFAULT_LINKER=/usr/bin/ld

# The staging output compiles the common Clang libraries and tidy checks once.
# Native install components keep the compiler and its SDK in the clang package.
cmake --build build --parallel "${CPU_COUNT}" \
	--target clangd clang-tidy clang-apply-replacements
for component in clangd clang-tidy clang-apply-replacements; do
	cmake --install build --component "${component}"
done
