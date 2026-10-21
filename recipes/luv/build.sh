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
	-DCMAKE_INSTALL_INCLUDEDIR="lib/devkit/include/luv-1.52.1" \
	-DCMAKE_INSTALL_DATAROOTDIR=lib/devkit/share \
	-DCMAKE_C_COMPILER="${CC}" -DCMAKE_C_FLAGS="${CFLAGS}" \
	-DCMAKE_AR="${AR}" -DCMAKE_RANLIB="${RANLIB}" \
	-DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}" \
	-DCMAKE_SHARED_LINKER_FLAGS="${LDFLAGS}" \
	-DCMAKE_MODULE_LINKER_FLAGS="${LDFLAGS}" \
	-DCMAKE_BUILD_RPATH="${PREFIX}/lib/devkit/lib" \
	-DCMAKE_INSTALL_RPATH_USE_LINK_PATH=OFF \
	"-DCMAKE_INSTALL_RPATH=\$ORIGIN;\$ORIGIN/../.." \
	-DBUILD_SHARED_LIBS=ON \
	-DLUA_BUILD_TYPE=System -DWITH_LUA_ENGINE=LuaJIT \
	-DWITH_SHARED_LIBUV=ON -DBUILD_MODULE=OFF -DBUILD_STATIC_LIBS=OFF \
	-DLUA_COMPAT53_DIR="${PREFIX}/lib/devkit/include/lua-compat-5.3-0.13" \
	-DLUAJIT_INCLUDE_DIR="${PREFIX}/lib/devkit/include/luajit-2.1.1774638290" \
	-DLUAJIT_LIBRARIES="${PREFIX}/lib/devkit/lib/libluajit-5.1.so" \
	-DLIBUV_INCLUDE_DIR="${PREFIX}/lib/devkit/include/libuv-1.52.1" \
	-DLIBUV_LIBRARIES="${PREFIX}/lib/devkit/lib/libuv.so" \
	-DSHAREDLIBS_INSTALL_LIB_DIR="${PREFIX}/lib/devkit/lib" \
	-DSHAREDLIBS_INSTALL_INC_DIR="${PREFIX}/lib/devkit/include/luv-1.52.1/luv"
cmake --build build --parallel "${CPU_COUNT}"
cmake --install build
mkdir -p "${PREFIX}/lib/devkit/lib/lua/5.1"
ln -sfn ../../libluv.so "${PREFIX}/lib/devkit/lib/lua/5.1/luv.so"
