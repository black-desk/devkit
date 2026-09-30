#!/usr/bin/env bash
set -euxo pipefail

: "${PCRE2_VERSION:?rattler-build must provide PCRE2_VERSION}"
: "${SYSROOT_TRIPLET:?rattler-build must provide SYSROOT_TRIPLET}"

test -x "${BUILD_PREFIX}/bin/gcc"
test -x "${BUILD_PREFIX}/bin/as"
test -x "${BUILD_PREFIX}/bin/ld"

SYSROOT="${BUILD_PREFIX}/${SYSROOT_TRIPLET}/sysroot"
test -d "${SYSROOT}"

cp "${BUILD_PREFIX}/share/gnuconfig/config.guess" config.guess
cp "${BUILD_PREFIX}/share/gnuconfig/config.sub" config.sub

export PATH="${BUILD_PREFIX}/bin:${PATH}"
export CC="${BUILD_PREFIX}/bin/gcc"
export CFLAGS="--sysroot=${SYSROOT} -O2 -pipe"
export LDFLAGS="--sysroot=${SYSROOT}"

./configure \
  --prefix="${PREFIX}" \
  --libdir="${PREFIX}/lib" \
  --includedir="${PREFIX}/include/pcre2-${PCRE2_VERSION}" \
  --enable-shared \
  --enable-static \
  --disable-pcre2-16 \
  --disable-pcre2-32 \
  --enable-jit \
  --disable-valgrind \
  --disable-coverage \
  --disable-fuzz-support \
  --disable-diff-fuzz-support

make -j"${CPU_COUNT}"
make check
make install

# The source patch keeps upstream's command-line interface while making its
# flag output relocatable and exact. Keep the generated helper private to this
# package instead of exposing it as a user command in ${PREFIX}/bin.
install -d -m 0755 "${PREFIX}/libexec/pcre2/bin"
mv "${PREFIX}/bin/pcre2-config" \
  "${PREFIX}/libexec/pcre2/bin/pcre2-config"

cat >"${PREFIX}/lib/pkgconfig/libpcre2-8.pc" <<EOF
prefix=\${pcfiledir}/../..
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: libpcre2-8
Description: PCRE2 - Perl compatible regular expressions C library (2nd API) with 8 bit character support
Version: ${PCRE2_VERSION}
License: BSD-3-Clause WITH PCRE2-exception
Cflags: -I\${includedir}/pcre2-${PCRE2_VERSION}
Cflags.private: -DPCRE2_STATIC
Libs: \${libdir}/libpcre2-8.so
Libs.private: -lm
EOF

cat >"${PREFIX}/lib/pkgconfig/libpcre2-posix.pc" <<EOF
prefix=\${pcfiledir}/../..
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: libpcre2-posix
Description: Posix compatible interface to libpcre2-8
Version: ${PCRE2_VERSION}
License: BSD-3-Clause WITH PCRE2-exception
Cflags: -I\${includedir}/pcre2-${PCRE2_VERSION}
Libs: \${libdir}/libpcre2-posix.so
Requires.private: libpcre2-8
EOF

cat >"${SRC_DIR}/devkit-consumer.c" <<'EOF'
#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>

#include <stdio.h>

int main(void) {
  int error_code;
  PCRE2_SIZE error_offset;
  pcre2_code *code = pcre2_compile(
    (PCRE2_SPTR)"devkit", PCRE2_ZERO_TERMINATED, 0,
    &error_code, &error_offset, NULL
  );
  if (code == NULL) {
    return 1;
  }
  pcre2_code_free(code);
  puts("pcre2");
  return 0;
}
EOF

"${CC}" \
  ${CFLAGS} \
  -I"${PREFIX}/include/pcre2-${PCRE2_VERSION}" \
  "${SRC_DIR}/devkit-consumer.c" \
  "${PREFIX}/lib/libpcre2-8.so" \
  -o "${SRC_DIR}/devkit-consumer"

LD_LIBRARY_PATH="${PREFIX}/lib" "${SRC_DIR}/devkit-consumer"
