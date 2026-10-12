#!/usr/bin/env bash
set -euxo pipefail
source "${SRC_DIR}/devkit-build/build-env.sh"
make -j"${CPU_COUNT}" PREFIX="${PREFIX}" INCLUDEDIR="${PREFIX}/include/lz4-${LIBRARY_VERSION}"
lz4_upstream_tests() {
  make -C tests datagen
  # Preserve conda-forge's corpus, including large and linked blocks.
  tests/datagen -g0 | ./lz4 -v | ./lz4 -t
  tests/datagen -g16KB | ./lz4 -9 | ./lz4 -t
  tests/datagen | ./lz4 | ./lz4 -t
  tests/datagen -g6M -P99 | ./lz4 -9BD | ./lz4 -t
  tests/datagen -g17M | ./lz4 -9v | ./lz4 -qt
  tests/datagen -g33M | ./lz4 --no-frame-crc | ./lz4 -t
  tests/datagen -g256MB | ./lz4 -vqB4D | ./lz4 -t
}
devkit_test lz4_upstream_tests
make install PREFIX="${PREFIX}" INCLUDEDIR="${PREFIX}/include/lz4-${LIBRARY_VERSION}"
python3 - <<'PY'
import os
from pathlib import Path
p = Path(os.environ['PREFIX']) / 'lib/pkgconfig/liblz4.pc'
lines = p.read_text().splitlines()
lines = ['prefix=${pcfiledir}/../..' if x.startswith('prefix=') else
         'exec_prefix=${prefix}' if x.startswith('exec_prefix=') else
         'libdir=${prefix}/lib' if x.startswith('libdir=') else
         'includedir=${prefix}/include/lz4-' + os.environ['LIBRARY_VERSION']
         if x.startswith('includedir=') else x for x in lines]
p.write_text(('\n'.join(lines) + '\n').replace('-L${libdir} -llz4', '${libdir}/liblz4.so'))
PY
"${CC}" ${CFLAGS} ${LDFLAGS} -I"${PREFIX}/include/lz4-${LIBRARY_VERSION}" \
  "${RECIPE_DIR}/tests/probe.c" "${PREFIX}/lib/liblz4.so" \
  '-Wl,--enable-new-dtags,-rpath,$ORIGIN/runtime-lib' -o library-probe
ln -s "${PREFIX}/lib" runtime-lib
./library-probe
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"
