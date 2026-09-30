#!/usr/bin/env bash
set -euxo pipefail

: "${EXPAT_VERSION:?rattler-build must provide EXPAT_VERSION}"
: "${SYSROOT_TRIPLET:?rattler-build must provide SYSROOT_TRIPLET}"

test -x "${BUILD_PREFIX}/bin/gcc"
test -x "${BUILD_PREFIX}/bin/as"
test -x "${BUILD_PREFIX}/bin/ld"

SYSROOT="${BUILD_PREFIX}/${SYSROOT_TRIPLET}/sysroot"
test -d "${SYSROOT}"

cp "${BUILD_PREFIX}/share/gnuconfig/config.guess" conftools/config.guess
cp "${BUILD_PREFIX}/share/gnuconfig/config.sub" conftools/config.sub

export PATH="${BUILD_PREFIX}/bin:${PATH}"
export CC="${BUILD_PREFIX}/bin/gcc"
export CFLAGS="--sysroot=${SYSROOT} -O2 -pipe"
export LDFLAGS="--sysroot=${SYSROOT}"

./configure \
  --prefix="${PREFIX}" \
  --libdir="${PREFIX}/lib" \
  --includedir="${PREFIX}/include/expat-${EXPAT_VERSION}" \
  --enable-shared \
  --enable-static \
  --without-examples \
  --without-tests \
  --without-docbook

make -j"${CPU_COUNT}"
make install

# Autotools' exported CMake target uses the shared include root even though
# this package installed Expat beneath a version-specific directory.
sed -i \
  "s#INTERFACE_INCLUDE_DIRECTORIES \"\${_IMPORT_PREFIX}/include\"#INTERFACE_INCLUDE_DIRECTORIES \"\${_IMPORT_PREFIX}/include/expat-${EXPAT_VERSION}\"#" \
  "${PREFIX}/lib/cmake/expat-${EXPAT_VERSION}/expat.cmake"

cat >"${PREFIX}/lib/pkgconfig/expat.pc" <<EOF
prefix=\${pcfiledir}/../..
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: expat
Description: expat XML parser
URL: https://libexpat.github.io/
Version: ${EXPAT_VERSION}
Cflags: -I\${includedir}/expat-${EXPAT_VERSION}
Cflags.private: -DXML_STATIC
Libs: \${libdir}/libexpat.so
EOF

cat >"${SRC_DIR}/devkit-consumer.c" <<'EOF'
#include <expat.h>

#include <stdio.h>
#include <string.h>

static void XMLCALL start(void *userData, const XML_Char *name, const XML_Char **atts) {
  (void)userData;
  (void)atts;
  puts(name);
}

int main(void) {
  XML_Parser parser = XML_ParserCreate(NULL);
  if (parser == NULL) {
    return 1;
  }
  XML_SetElementHandler(parser, start, NULL);
  const char *document = "<devkit/>";
  if (XML_Parse(parser, document, (int)strlen(document), 1) == XML_STATUS_ERROR) {
    XML_ParserFree(parser);
    return 1;
  }
  XML_ParserFree(parser);
  return 0;
}
EOF

"${CC}" \
  ${CFLAGS} \
  -I"${PREFIX}/include/expat-${EXPAT_VERSION}" \
  "${SRC_DIR}/devkit-consumer.c" \
  "${PREFIX}/lib/libexpat.so" \
  -Wl,-rpath-link,"${SYSROOT}/lib64" \
  -o "${SRC_DIR}/devkit-consumer"

LD_LIBRARY_PATH="${PREFIX}/lib" "${SRC_DIR}/devkit-consumer"
