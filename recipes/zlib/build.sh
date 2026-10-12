#!/usr/bin/env bash
set -euxo pipefail

: "${ZLIB_VERSION:?rattler-build must provide ZLIB_VERSION}"
: "${SYSROOT_TRIPLET:?rattler-build must provide SYSROOT_TRIPLET}"

source "${SRC_DIR}/devkit-build/build-env.sh"

# TODO: Remove this recipe-local workaround when zlib fixes its shared-library
# configure probe, which applies zlib.map to an object lacking its symbols.
# Follow the workaround merged in https://github.com/NixOS/nixpkgs/pull/307540.
# Upstream: https://github.com/madler/zlib/issues/960
# Upstream: https://github.com/madler/zlib/issues/1318
export LDFLAGS="${LDFLAGS} -Wl,--undefined-version"

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
  ${CFLAGS} ${LDFLAGS} \
  -I"${PREFIX}/include/zlib-${ZLIB_VERSION}" \
  "${SRC_DIR}/devkit-consumer.c" \
  "${PREFIX}/lib/libz.so" \
  -o "${SRC_DIR}/devkit-consumer"

env -u LD_LIBRARY_PATH -u LD_PRELOAD "${SRC_DIR}/devkit-consumer"

python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"
