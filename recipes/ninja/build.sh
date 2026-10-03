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

python configure.py --bootstrap
install -Dm755 ninja "${PREFIX}/bin/ninja"
