#!/usr/bin/env bash
set -euxo pipefail
source "${SRC_DIR}/devkit-build/build-env.sh"
unset LD_LIBRARY_PATH LD_PRELOAD
unset PYTHON
export CPPFLAGS="${CPPFLAGS} -I${PREFIX}/include/libiconv-1.18 -I${PREFIX}/include/zlib-1.3.2"
export LDFLAGS="${LDFLAGS} -L${PREFIX}/lib/llvm-runtime -lgcc_s -liconv -Wl,-rpath,${SRC_DIR}/.libs"
export PKG_CONFIG="${BUILD_PREFIX}/bin/pkgconf"
export PKG_CONFIG_LIBDIR="${PREFIX}/lib/pkgconfig"
unset PKG_CONFIG_PATH
cp "${BUILD_PREFIX}/share/gnuconfig/config.guess" config.guess
cp "${BUILD_PREFIX}/share/gnuconfig/config.sub" config.sub
# FTP and LZMA were removed upstream before/in 2.15; the forge recipe's old
# options no longer enable them. --with-tls means thread-local storage.
./configure --prefix="${PREFIX}" --with-iconv --with-zlib --with-icu \
  --with-legacy --with-python=no --with-tls --enable-static=no \
  --with-schematron=yes
# Libtool's -no-install builds executables with build-tree RUNPATH instead of
# loader-environment shell wrappers. Finalization replaces that RUNPATH.
make -j"${CPU_COUNT}" AM_LDFLAGS=-no-install
devkit_test make check AM_LDFLAGS=-no-install
make install AM_LDFLAGS=-no-install
mv "${PREFIX}/include/libxml2" "${PREFIX}/include/libxml2-${LIBRARY_VERSION}"
python3 - <<'PY'
import os
from pathlib import Path
prefix = Path(os.environ['PREFIX'])
version = os.environ['LIBRARY_VERSION']
paths = [prefix / 'bin/xml2-config', prefix / 'lib/pkgconfig/libxml-2.0.pc']
paths.extend(prefix.glob('lib/cmake/libxml2*/*.cmake'))
for path in paths:
    text = path.read_text().replace('/include/libxml2', '/include/libxml2-' + version)
    text = text.replace('${includedir}/libxml2', '${includedir}/libxml2-' + version)
    path.write_text(text)
PY
rm -f "${PREFIX}/lib/libxml2.la"
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"
