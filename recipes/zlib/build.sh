#!/usr/bin/env bash
set -euxo pipefail

: "${ZLIB_VERSION:?rattler-build must provide ZLIB_VERSION}"
: "${SYSROOT_TRIPLET:?rattler-build must provide SYSROOT_TRIPLET}"

test -x "${BUILD_PREFIX}/bin/gcc"
test -x "${BUILD_PREFIX}/bin/as"
test -x "${BUILD_PREFIX}/bin/ld"

SYSROOT="${BUILD_PREFIX}/${SYSROOT_TRIPLET}/sysroot"
test -d "${SYSROOT}"

export PATH="${BUILD_PREFIX}/bin:${PATH}"
export CC="${BUILD_PREFIX}/bin/gcc"
export CFLAGS="--sysroot=${SYSROOT} -O2 -pipe -fPIC"
export LDFLAGS="--sysroot=${SYSROOT}"

BUILD_DIR="${SRC_DIR}/build"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

../configure \
  --prefix="${PREFIX}" \
  --libdir="${PREFIX}/lib" \
  --includedir="${PREFIX}/include/zlib-${ZLIB_VERSION}"

make -j"${CPU_COUNT}"
make test
make install

cat >"${PREFIX}/lib/pkgconfig/zlib.pc" <<EOF
prefix=\${pcfiledir}/../..
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: zlib
Description: zlib compression library
Version: ${ZLIB_VERSION}
License: Zlib
Cflags: -I\${includedir}/zlib-${ZLIB_VERSION}
Libs: \${libdir}/libz.so
EOF

cat >"${SRC_DIR}/devkit-consumer.c" <<'EOF'
#include <zlib.h>

#include <stdio.h>

int main(void) {
  z_stream stream = {0};
  if (deflateInit(&stream, 1) != Z_OK) {
    return 1;
  }
  printf("%s\n", zlibVersion());
  deflateEnd(&stream);
  return 0;
}
EOF

"${CC}" \
  ${CFLAGS} \
  -I"${PREFIX}/include/zlib-${ZLIB_VERSION}" \
  "${SRC_DIR}/devkit-consumer.c" \
  "${PREFIX}/lib/libz.so" \
  -o "${SRC_DIR}/devkit-consumer"

LD_LIBRARY_PATH="${PREFIX}/lib" "${SRC_DIR}/devkit-consumer"
