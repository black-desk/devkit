#!/usr/bin/env bash
set -euxo pipefail

: "${EXPAT_VERSION:?rattler-build must provide EXPAT_VERSION}"
: "${SYSROOT_TRIPLET:?rattler-build must provide SYSROOT_TRIPLET}"

source "${SRC_DIR}/devkit-build/build-env.sh"

cp "${BUILD_PREFIX}/share/gnuconfig/config.guess" conftools/config.guess
cp "${BUILD_PREFIX}/share/gnuconfig/config.sub" conftools/config.sub

./configure \
  --prefix="${PREFIX}" \
  --libdir="${PREFIX}/lib" \
  --includedir="${PREFIX}/include/expat-${EXPAT_VERSION}" \
  --enable-shared \
  --enable-static \
  --without-docbook

make -j"${CPU_COUNT}"
make check
make install

# Autotools' exported CMake target uses the shared include root even though
# this package installed Expat beneath a version-specific directory.
python3 - <<'PYCODE'
import os
from pathlib import Path
p = Path(os.environ['PREFIX']) / ('lib/cmake/expat-' + os.environ['EXPAT_VERSION']) / 'expat.cmake'
s = p.read_text()
old = 'INTERFACE_INCLUDE_DIRECTORIES "${_IMPORT_PREFIX}/include"'
new = 'INTERFACE_INCLUDE_DIRECTORIES "${_IMPORT_PREFIX}/include/expat-' + os.environ['EXPAT_VERSION'] + '"'
assert old in s
p.write_text(s.replace(old, new))
PYCODE

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
  ${CFLAGS} ${LDFLAGS} \
  -I"${PREFIX}/include/expat-${EXPAT_VERSION}" \
  "${SRC_DIR}/devkit-consumer.c" \
  "${PREFIX}/lib/libexpat.so" \
  -Wl,-rpath-link,"${SYSROOT}/lib64" \
  '-Wl,--enable-new-dtags,-rpath,$ORIGIN/runtime-lib' \
  -o "${SRC_DIR}/library-probe"

ln -s "${PREFIX}/lib" runtime-lib

env -u LD_LIBRARY_PATH -u LD_PRELOAD "${SRC_DIR}/library-probe"

python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"
