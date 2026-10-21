#!/usr/bin/env bash
set -euxo pipefail

export PATH="${BUILD_PREFIX}/bin:${PATH}"
export CC="${BUILD_PREFIX}/bin/clang"
export AR="${BUILD_PREFIX}/bin/llvm-ar"
export RANLIB="${BUILD_PREFIX}/bin/llvm-ranlib"
export CFLAGS="--no-default-config --config=${BUILD_PREFIX}/lib/devkit/share/devkit/clang.cfg -O2 -fPIC"
export CPPFLAGS=""
export LDFLAGS="-L${PREFIX}/lib/devkit/lib -Wl,-rpath-link,${PREFIX}/lib/devkit/lib"
export PKG_CONFIG="${BUILD_PREFIX}/bin/pkg-config"
export PKG_CONFIG_LIBDIR="${PREFIX}/lib/devkit/lib/pkgconfig"
export PKG_CONFIG_PATH="${PKG_CONFIG_LIBDIR}"

cmake -S . -B build -G Ninja \
	-DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
	-DCMAKE_PREFIX_PATH="${PREFIX}/lib/devkit" \
	-DCMAKE_INSTALL_LIBDIR=lib/devkit/lib \
	-DCMAKE_INSTALL_INCLUDEDIR="lib/devkit/include/libtree-sitter-0.26.13" \
	-DCMAKE_INSTALL_DATAROOTDIR=lib/devkit/share \
	-DCMAKE_C_COMPILER="${CC}" -DCMAKE_C_FLAGS="${CFLAGS}" \
	-DCMAKE_AR="${AR}" -DCMAKE_RANLIB="${RANLIB}" \
	-DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}" \
	-DCMAKE_SHARED_LINKER_FLAGS="${LDFLAGS}" \
	-DCMAKE_MODULE_LINKER_FLAGS="${LDFLAGS}" \
	-DCMAKE_BUILD_RPATH="${PREFIX}/lib/devkit/lib" \
	-DCMAKE_INSTALL_RPATH_USE_LINK_PATH=OFF \
	"-DCMAKE_INSTALL_RPATH=\$ORIGIN" \
	-DBUILD_SHARED_LIBS=ON
cmake --build build --parallel "${CPU_COUNT}"
cmake --install build
