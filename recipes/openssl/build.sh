#!/usr/bin/env bash
set -euxo pipefail

: "${OPENSSL_VERSION:?rattler-build must provide OPENSSL_VERSION}"
: "${SYSROOT_TRIPLET:?rattler-build must provide SYSROOT_TRIPLET}"

test -x "${BUILD_PREFIX}/bin/gcc"
test -x "${BUILD_PREFIX}/bin/as"
test -x "${BUILD_PREFIX}/bin/ld"
test -x "${BUILD_PREFIX}/bin/perl"

SYSROOT="${BUILD_PREFIX}/${SYSROOT_TRIPLET}/sysroot"
test -d "${SYSROOT}"

export PATH="${BUILD_PREFIX}/bin:${PATH}"
export CC="${BUILD_PREFIX}/bin/gcc"
export CFLAGS="--sysroot=${SYSROOT} -O2 -pipe"
export LDFLAGS="--sysroot=${SYSROOT}"

# OpenSSL's Configure and build machinery is Perl-based.
"${BUILD_PREFIX}/bin/perl" ./Configure \
  linux-x86_64 \
  --prefix="${PREFIX}" \
  --openssldir="${PREFIX}/etc/ssl" \
  --libdir=lib \
  enable-legacy \
  shared \
  no-docs \
  no-zlib

make -j"${CPU_COUNT}"
make test
make install

# These Perl helpers would make the OpenSSL runtime pull in Perl. The channel
# needs the C libraries and the OpenSSL CLI here; Perl remains a build input.
rm -f "${PREFIX}/bin/c_rehash"
rm -rf "${PREFIX}/etc/ssl/misc"

# OpenSSL installs its public headers as include/openssl/*.h. Keep that inner
# upstream layout, but expose it only through a package- and version-specific
# include root so a broad -I${PREFIX}/include cannot discover it accidentally.
install -d -m 0755 "${PREFIX}/include/openssl-${OPENSSL_VERSION}"
mv "${PREFIX}/include/openssl" \
  "${PREFIX}/include/openssl-${OPENSSL_VERSION}/openssl"

# The generated CMake package derives its interface include directory from the
# upstream installation layout. Correct it to the isolated devkit root.
sed -i \
  "s#set(OPENSSL_INCLUDE_DIR \"\${_ossl_prefix}/include\")#set(OPENSSL_INCLUDE_DIR \"\${_ossl_prefix}/include/openssl-${OPENSSL_VERSION}\")#" \
  "${PREFIX}/lib/cmake/OpenSSL/OpenSSLConfig.cmake"

cat >"${PREFIX}/lib/pkgconfig/libcrypto.pc" <<EOF
prefix=\${pcfiledir}/../..
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: OpenSSL-libcrypto
Description: OpenSSL cryptography library
Version: ${OPENSSL_VERSION}
License: Apache-2.0
Cflags: -I\${includedir}/openssl-${OPENSSL_VERSION}
Libs: \${libdir}/libcrypto.so
Libs.private: -ldl -pthread
EOF

cat >"${PREFIX}/lib/pkgconfig/libssl.pc" <<EOF
prefix=\${pcfiledir}/../..
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: OpenSSL-libssl
Description: Secure Sockets Layer and cryptography libraries
Version: ${OPENSSL_VERSION}
License: Apache-2.0
Requires.private: libcrypto
Cflags: -I\${includedir}/openssl-${OPENSSL_VERSION}
Libs: \${libdir}/libssl.so
Libs.private: \${libdir}/libcrypto.so -ldl -pthread
EOF

cat >"${PREFIX}/lib/pkgconfig/openssl.pc" <<EOF
prefix=\${pcfiledir}/../..
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: OpenSSL
Description: Secure Sockets Layer and cryptography libraries
Version: ${OPENSSL_VERSION}
License: Apache-2.0
Requires: libssl libcrypto
Cflags: -I\${includedir}/openssl-${OPENSSL_VERSION}
Libs: \${libdir}/libssl.so \${libdir}/libcrypto.so
Libs.private: -ldl -pthread
EOF

# OpenSSL looks for a single default PEM bundle beside its configuration file.
# The ca-certificates package owns the actual pinned bundle.
ln -s certs/ca-certificates.crt "${PREFIX}/etc/ssl/cert.pem"

cat >"${SRC_DIR}/devkit-consumer.c" <<'EOF'
#include <openssl/crypto.h>
#include <openssl/ssl.h>
#include <openssl/opensslv.h>

#include <stdio.h>

int main(void) {
  if (OPENSSL_VERSION_NUMBER != OpenSSL_version_num()) {
    return 1;
  }
  SSL_CTX *context = SSL_CTX_new(TLS_client_method());
  if (context == NULL) {
    return 1;
  }
  SSL_CTX_free(context);
  puts(OPENSSL_VERSION_TEXT);
  return 0;
}
EOF

"${CC}" \
  ${CFLAGS} \
  -I"${PREFIX}/include/openssl-${OPENSSL_VERSION}" \
  "${SRC_DIR}/devkit-consumer.c" \
  "${PREFIX}/lib/libssl.so" \
  "${PREFIX}/lib/libcrypto.so" \
  -ldl \
  -pthread \
  -o "${SRC_DIR}/devkit-consumer"

LD_LIBRARY_PATH="${PREFIX}/lib" "${SRC_DIR}/devkit-consumer"
