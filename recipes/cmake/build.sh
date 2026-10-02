#!/usr/bin/env bash
set -euxo pipefail

: "${CMAKE_VERSION:?rattler-build must provide CMAKE_VERSION}"
: "${OPENSSL_VERSION:?rattler-build must provide OPENSSL_VERSION}"
: "${SYSROOT_TRIPLET:?rattler-build must provide SYSROOT_TRIPLET}"

test -x "${BUILD_PREFIX}/bin/gcc"
test -x "${BUILD_PREFIX}/bin/g++"
test -x "${BUILD_PREFIX}/bin/as"
test -x "${BUILD_PREFIX}/bin/ld"
test -x "${BUILD_PREFIX}/bin/make"
test -x "${BUILD_PREFIX}/bin/pkg-config"
test -d "${BUILD_PREFIX}/include/openssl-${OPENSSL_VERSION}"
test -f "${BUILD_PREFIX}/lib/libssl.so"
test -f "${BUILD_PREFIX}/lib/libcrypto.so"

SYSROOT="${BUILD_PREFIX}/${SYSROOT_TRIPLET}/sysroot"
test -d "${SYSROOT}"

export PATH="${BUILD_PREFIX}/bin:${PATH}"
export CC="${BUILD_PREFIX}/bin/gcc"
export CXX="${BUILD_PREFIX}/bin/g++"
export CFLAGS="--sysroot=${SYSROOT} -O2 -pipe"
export CXXFLAGS="--sysroot=${SYSROOT} -O2 -pipe"
export LDFLAGS="--sysroot=${SYSROOT} -pthread -Wl,-rpath-link,${SYSROOT}/lib64"
export PKG_CONFIG_PATH="${BUILD_PREFIX}/lib/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"

# CMake's bootstrap compiler builds a first cmake executable, which then
# regenerates and builds the complete release. Most third-party sources remain
# bundled; OpenSSL is supplied by the channel so CMake's downloader keeps TLS.
./bootstrap \
  --prefix="${PREFIX}" \
  --parallel="${CPU_COUNT}" \
  --generator="Unix Makefiles" \
  --no-system-libs \
  --no-qt-gui \
  -- \
  -DBUILD_TESTING=OFF \
  -DCMAKE_USE_OPENSSL=ON

make -j"${CPU_COUNT}"
make install

"${BUILD_PREFIX}/bin/strip" --strip-unneeded \
  "${PREFIX}/bin/cmake" \
  "${PREFIX}/bin/ctest" \
  "${PREFIX}/bin/cpack"
