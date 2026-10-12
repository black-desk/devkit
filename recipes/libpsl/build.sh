#!/usr/bin/env bash
set -euxo pipefail
source "${SRC_DIR}/devkit-build/build-env.sh"
cp "${BUILD_PREFIX}/share/gnuconfig/"config.* .
export PKG_CONFIG="${BUILD_PREFIX}/bin/pkgconf"
export PKG_CONFIG_LIBDIR="${PREFIX}/lib/pkgconfig"
unset PKG_CONFIG_PATH PYTHON
export CPPFLAGS="${CPPFLAGS} $(${PKG_CONFIG} --cflags icu-uc)"
export LDFLAGS="${LDFLAGS} -Wl,-rpath,${SRC_DIR}/src/.libs"
# The release contains these generated files. Upstream configure explicitly
# requires Python only if any are absent; keep all built-in data and tests.
test -f src/suffixes_dafsa.h
test -f tests/psl.dafsa
test -f tests/psl_ascii.dafsa
./configure --prefix="${PREFIX}" --includedir="${PREFIX}/include/libpsl-${LIBRARY_VERSION}" \
  --enable-runtime=libicu --enable-builtin --disable-static
make -j"${CPU_COUNT}" AM_LDFLAGS=-no-install
make check AM_LDFLAGS=-no-install
make install AM_LDFLAGS=-no-install
rm -f "${PREFIX}/lib/libpsl.la"
# The seed carrier excludes this Python data-regeneration helper too.
# Retain the compiled library, built-in data and native psl command.
rm -f "${PREFIX}/bin/psl-make-dafsa" "${PREFIX}/share/man/man1/psl-make-dafsa.1"
python3 - <<'PY'
import os
from pathlib import Path
p = Path(os.environ['PREFIX']) / 'lib/pkgconfig/libpsl.pc'
lines = p.read_text().splitlines()
lines = ['prefix=${pcfiledir}/../..' if x.startswith('prefix=') else
         'exec_prefix=${prefix}' if x.startswith('exec_prefix=') else
         'libdir=${prefix}/lib' if x.startswith('libdir=') else
         'includedir=${prefix}/include/libpsl-' + os.environ['LIBRARY_VERSION']
         if x.startswith('includedir=') else x for x in lines]
p.write_text(('\n'.join(lines) + '\n').replace('-L${libdir} -lpsl', '${libdir}/libpsl.so'))
PY
"${CC}" ${CFLAGS} ${LDFLAGS} -I"${PREFIX}/include/libpsl-${LIBRARY_VERSION}" \
  "${RECIPE_DIR}/tests/probe.c" "${PREFIX}/lib/libpsl.so" \
  '-Wl,--enable-new-dtags,-rpath,$ORIGIN/runtime-lib' -o library-probe
mkdir runtime-lib
ln -s "${PREFIX}/lib/libpsl.so.5" runtime-lib/libpsl.so.5
./library-probe
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"
