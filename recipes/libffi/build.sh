#!/usr/bin/env bash
set -euxo pipefail

SYSROOT="${BUILD_PREFIX}/x86_64-pc-linux-gnu/sysroot"
test -d "${SYSROOT}"
export PATH="${BUILD_PREFIX}/bin:${PATH}"
export CC="${BUILD_PREFIX}/bin/gcc"
export CXX="${BUILD_PREFIX}/bin/g++"
export CFLAGS="--sysroot=${SYSROOT} -O2 -pipe -fPIC"
export CXXFLAGS="${CFLAGS}"
export LDFLAGS="--sysroot=${SYSROOT} -Wl,-rpath,${PREFIX}/lib"
export PKG_CONFIG="${BUILD_PREFIX}/bin/pkg-config"
export PKG_CONFIG_LIBDIR="${PREFIX}/lib/pkgconfig:${PREFIX}/share/pkgconfig"
export PKG_CONFIG_PATH="${PKG_CONFIG_LIBDIR}"
export LD_LIBRARY_PATH="${PREFIX}/lib:${BUILD_PREFIX}/lib"

cp "${BUILD_PREFIX}/share/gnuconfig/config.guess" config.guess
cp "${BUILD_PREFIX}/share/gnuconfig/config.sub" config.sub
./configure --prefix="${PREFIX}" --libdir="${PREFIX}/lib" \
	--includedir="${PREFIX}/include/libffi-${PKG_VERSION}" \
	--disable-static --disable-docs --disable-multi-os-directory
make -j"${CPU_COUNT}"
make install
rm -f "${PREFIX}/lib/libffi.la"
cat >"${PREFIX}/lib/pkgconfig/libffi.pc" <<EOF
prefix=\${pcfiledir}/../..
libdir=\${prefix}/lib
includedir=\${prefix}/include/libffi-${PKG_VERSION}

Name: libffi
Description: Foreign function interface
Version: ${PKG_VERSION}
Libs: \${libdir}/libffi.so
Cflags: -I\${includedir}
EOF
