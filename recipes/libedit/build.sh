#!/usr/bin/env bash
set -euxo pipefail
source "${SRC_DIR}/devkit-build/build-env.sh"
cp "${BUILD_PREFIX}/share/gnuconfig/"config.* .
export CPPFLAGS="${CPPFLAGS} -I${PREFIX}/include/ncurses-6.6 -I${PREFIX}/include/ncurses-6.6/ncurses"
export LDFLAGS="${LDFLAGS} -Wl,-rpath,${SRC_DIR}/src/.libs"
# Match the seed's shared-only library configuration.
./configure --prefix="${PREFIX}" --includedir="${PREFIX}/include/libedit-${LIBRARY_VERSION}" --disable-static
make -j"${CPU_COUNT}" AM_LDFLAGS=-no-install
devkit_test make check AM_LDFLAGS=-no-install
make install AM_LDFLAGS=-no-install
# The seed also avoids the manual-page name shared with readline.
rm -f "${PREFIX}/share/man/man3/history.3" "${PREFIX}/lib/libedit.la"
python3 - <<'PY'
import os
from pathlib import Path
p = Path(os.environ['PREFIX']) / 'lib/pkgconfig/libedit.pc'
lines = p.read_text().splitlines()
lines = ['prefix=${pcfiledir}/../..' if x.startswith('prefix=') else
         'exec_prefix=${prefix}' if x.startswith('exec_prefix=') else
         'libdir=${prefix}/lib' if x.startswith('libdir=') else
         'includedir=${prefix}/include/libedit-' + os.environ['LIBRARY_VERSION']
         if x.startswith('includedir=') else x for x in lines]
p.write_text(('\n'.join(lines) + '\n').replace('-L${libdir} -ledit', '${libdir}/libedit.so'))
PY
"${CC}" ${CFLAGS} ${LDFLAGS} -I"${PREFIX}/include/libedit-${LIBRARY_VERSION}" \
  "${RECIPE_DIR}/tests/probe.c" "${PREFIX}/lib/libedit.so" \
  '-Wl,--enable-new-dtags,-rpath,$ORIGIN/runtime-lib' -o library-probe
mkdir runtime-lib
ln -s "${PREFIX}/lib/libedit.so.0" runtime-lib/libedit.so.0
./library-probe
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"
