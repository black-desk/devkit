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
	-DCMAKE_INSTALL_INCLUDEDIR="lib/devkit/include/neovim-0.12.6" \
	-DCMAKE_INSTALL_DATAROOTDIR=lib/devkit/share \
	-DCMAKE_C_COMPILER="${CC}" -DCMAKE_C_FLAGS="${CFLAGS}" \
	-DCMAKE_AR="${AR}" -DCMAKE_RANLIB="${RANLIB}" \
	-DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}" \
	-DCMAKE_SHARED_LINKER_FLAGS="${LDFLAGS}" \
	-DCMAKE_MODULE_LINKER_FLAGS="${LDFLAGS}" \
	-DCMAKE_BUILD_RPATH="${PREFIX}/lib/devkit/lib" \
	-DCMAKE_INSTALL_RPATH_USE_LINK_PATH=OFF \
	"-DCMAKE_INSTALL_RPATH=\$ORIGIN/../lib/devkit/lib" \
	-DBUILD_SHARED_LIBS=ON \
	-DCMAKE_INSTALL_MANDIR=lib/devkit/share/man \
	-DDEPS_PREFIX="${SRC_DIR}/no-bundled-deps" \
	-DLUA_PRG="${BUILD_PREFIX}/bin/luajit" \
	-DLUAJIT_INCLUDE_DIR="${PREFIX}/lib/devkit/include/luajit-2.1.1774638290" \
	-DLUAJIT_LIBRARY="${PREFIX}/lib/devkit/lib/libluajit-5.1.so" \
	-DLUV_INCLUDE_DIR="${PREFIX}/lib/devkit/include/luv-1.52.1" \
	-DLUV_LIBRARY="${PREFIX}/lib/devkit/lib/libluv.so" \
	-DLPEG_LIBRARY="${PREFIX}/lib/devkit/lib/liblpeg.so" \
	-DLIBUV_INCLUDE_DIR="${PREFIX}/lib/devkit/include/libuv-1.52.1" \
	-DLIBUV_LIBRARY="${PREFIX}/lib/devkit/lib/libuv.so" \
	-DICONV_INCLUDE_DIR="${PREFIX}/lib/devkit/include/libiconv-1.18" \
	-DICONV_LIBRARY="${PREFIX}/lib/devkit/lib/libiconv.so" \
	-DUNIBILIUM_INCLUDE_DIR="${PREFIX}/lib/devkit/include/unibilium-2.1.2" \
	-DUNIBILIUM_LIBRARY="${PREFIX}/lib/devkit/lib/libunibilium.so" \
	-DUTF8PROC_INCLUDE_DIR="${PREFIX}/lib/devkit/include/libutf8proc-2.11.3" \
	-DUTF8PROC_LIBRARY="${PREFIX}/lib/devkit/lib/libutf8proc.so" \
	-DTREESITTER_INCLUDE_DIR="${PREFIX}/lib/devkit/include/libtree-sitter-0.26.13" \
	-DTREESITTER_LIBRARY="${PREFIX}/lib/devkit/lib/libtree-sitter.so" \
	-DENABLE_TRANSLATIONS=ON
cmake --build build --parallel "${CPU_COUNT}"
cmake --install build
