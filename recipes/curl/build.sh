#!/usr/bin/env bash
set -euxo pipefail

: "${CURL_VERSION:?rattler-build must provide CURL_VERSION}"
: "${OPENSSL_VERSION:?rattler-build must provide OPENSSL_VERSION}"
: "${ZLIB_VERSION:?rattler-build must provide ZLIB_VERSION}"
: "${SYSROOT_TRIPLET:?rattler-build must provide SYSROOT_TRIPLET}"

test -x "${BUILD_PREFIX}/bin/gcc"
test -x "${BUILD_PREFIX}/bin/as"
test -x "${BUILD_PREFIX}/bin/ld"
test -x "${BUILD_PREFIX}/bin/make"
test -x "${BUILD_PREFIX}/bin/pkg-config"

SYSROOT="${BUILD_PREFIX}/${SYSROOT_TRIPLET}/sysroot"
test -d "${SYSROOT}"
test -d "${BUILD_PREFIX}/include/openssl-${OPENSSL_VERSION}"
test -d "${BUILD_PREFIX}/include/zlib-${ZLIB_VERSION}"
test -f "${BUILD_PREFIX}/lib/libssl.so"
test -f "${BUILD_PREFIX}/lib/libcrypto.so"
test -f "${BUILD_PREFIX}/lib/libz.so"

export PATH="${BUILD_PREFIX}/bin:${PATH}"
export PKG_CONFIG="${BUILD_PREFIX}/bin/pkg-config"
export PKG_CONFIG_PATH="${BUILD_PREFIX}/lib/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"
export CC="${BUILD_PREFIX}/bin/gcc"
export CFLAGS="--sysroot=${SYSROOT} -O2 -pipe"
export LDFLAGS="--sysroot=${SYSROOT} -Wl,-rpath-link,${SYSROOT}/lib64"
CURL_EXACT_PRIVATE_LIBS="-Wl,${BUILD_PREFIX}/lib/libssl.so \
  -Wl,${BUILD_PREFIX}/lib/libcrypto.so \
  -Wl,${BUILD_PREFIX}/lib/libz.so \
  -pthread"

# Autotools consumes the exact include and library paths published by the
# channel's OpenSSL and zlib pkg-config metadata.
./configure \
  --prefix="${PREFIX}" \
  --libdir="${PREFIX}/lib" \
  --includedir="${PREFIX}/include/curl-${CURL_VERSION}" \
  --enable-shared \
  --enable-static \
  --with-openssl \
  --with-zlib \
  --with-ca-bundle="${PREFIX}/etc/ssl/certs/ca-certificates.crt" \
  --without-ca-path \
  --without-ca-fallback \
  --without-nghttp2 \
  --without-ngtcp2 \
  --without-quiche \
  --without-libidn2 \
  --without-libpsl \
  --without-libssh \
  --without-libssh2 \
  --without-gssapi \
  --without-brotli \
  --without-zstd \
  --disable-ares \
  --disable-ldap \
  --disable-ldaps \
  --disable-docs \
  --disable-manual

# Libtool drops bare library paths while composing libcurl.so. Passing the
# pkg-config-selected paths through -Wl keeps OpenSSL and zlib in NEEDED.
make -j"${CPU_COUNT}" LIBCURL_PC_LIBS_PRIVATE="${CURL_EXACT_PRIVATE_LIBS}"
make install LIBCURL_PC_LIBS_PRIVATE="${CURL_EXACT_PRIVATE_LIBS}"

# Keep the corrected upstream helper, but do not expose it as a user command.
install -d -m 0755 "${PREFIX}/libexec/curl/bin"
mv "${PREFIX}/bin/curl-config" \
  "${PREFIX}/libexec/curl/bin/curl-config"

# Autotools does not install a downstream CMake package. Remove the directory
# defensively so a future build-system change cannot expose generic paths.
rm -rf "${PREFIX}/lib/cmake/CURL"
rm -f "${PREFIX}/lib/libcurl.la"

cat >"${PREFIX}/lib/pkgconfig/libcurl.pc" <<EOF
prefix=\${pcfiledir}/../..
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: libcurl
URL: https://curl.se/
Description: Library to transfer files with HTTP, FTP, etc.
License: curl
Version: ${CURL_VERSION}
Cflags: -I\${includedir}/curl-${CURL_VERSION}
Libs: \${libdir}/libcurl.so
Libs.private: \${libdir}/libssl.a \${libdir}/libcrypto.a \${libdir}/libz.a -ldl -pthread
Link.ABI: c
EOF

# Remove auxiliary scripts that are not part of the initial Git-oriented tool.
rm -f "${PREFIX}/bin/wcurl"

cat >"${SRC_DIR}/devkit-consumer.c" <<'EOF'
#include <curl/curl.h>

#include <stdio.h>

int main(void) {
  if (curl_global_init(CURL_GLOBAL_DEFAULT) != CURLE_OK) {
    return 1;
  }

  CURL *curl = curl_easy_init();
  if (curl == NULL) {
    return 1;
  }
  curl_easy_cleanup(curl);
  curl_global_cleanup();
  puts("libcurl");
  return 0;
}
EOF

"${CC}" \
  ${CFLAGS} \
  -I"${PREFIX}/include/curl-${CURL_VERSION}" \
  "${SRC_DIR}/devkit-consumer.c" \
  "${PREFIX}/lib/libcurl.so" \
  ${LDFLAGS} \
  -o "${SRC_DIR}/devkit-consumer-shared"

LD_LIBRARY_PATH="${PREFIX}/lib" "${SRC_DIR}/devkit-consumer-shared"

"${CC}" \
  ${CFLAGS} \
  -I"${PREFIX}/include/curl-${CURL_VERSION}" \
  -I"${BUILD_PREFIX}/include/openssl-${OPENSSL_VERSION}" \
  -I"${BUILD_PREFIX}/include/zlib-${ZLIB_VERSION}" \
  "${SRC_DIR}/devkit-consumer.c" \
  "${PREFIX}/lib/libcurl.a" \
  "${BUILD_PREFIX}/lib/libssl.a" \
  "${BUILD_PREFIX}/lib/libcrypto.a" \
  "${BUILD_PREFIX}/lib/libz.a" \
  -ldl \
  -pthread \
  -o "${SRC_DIR}/devkit-consumer-static"

"${SRC_DIR}/devkit-consumer-static"
