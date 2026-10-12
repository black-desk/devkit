#!/usr/bin/env bash
set -euxo pipefail
source "${SRC_DIR}/devkit-build/build-env.sh"
cmake -S . -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_INSTALL_INCLUDEDIR="include/lzo-${LIBRARY_VERSION}" \
  -DCMAKE_C_COMPILER="${CC}" -DCMAKE_C_FLAGS="${CFLAGS}" \
  -DCMAKE_AR="${AR}" -DCMAKE_RANLIB="${RANLIB}" \
  -DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}" -DCMAKE_SHARED_LINKER_FLAGS="${LDFLAGS}" \
  '-DCMAKE_INSTALL_RPATH=$ORIGIN:$ORIGIN/../lib' \
  -DENABLE_SHARED=ON -DENABLE_STATIC=ON
cmake --build build --parallel "${CPU_COUNT}"
devkit_test ctest --test-dir build --output-on-failure
cmake --install build
python3 - <<'PY'
import os
from pathlib import Path
p = Path(os.environ['PREFIX']) / 'lib/pkgconfig/lzo2.pc'
lines = p.read_text().splitlines()
lines = ['prefix=${pcfiledir}/../..' if x.startswith('prefix=') else
         'exec_prefix=${prefix}' if x.startswith('exec_prefix=') else
         'libdir=${prefix}/lib' if x.startswith('libdir=') else
         'includedir=${prefix}/include/lzo-' + os.environ['LIBRARY_VERSION']
         if x.startswith('includedir=') else x for x in lines]
p.write_text(('\n'.join(lines) + '\n').replace('-L${libdir} -llzo2', '${libdir}/liblzo2.so'))
PY
"${CC}" ${CFLAGS} ${LDFLAGS} -I"${PREFIX}/include/lzo-${LIBRARY_VERSION}" \
  "${RECIPE_DIR}/tests/probe.c" "${PREFIX}/lib/liblzo2.so" \
  '-Wl,--enable-new-dtags,-rpath,$ORIGIN/runtime-lib' -o library-probe
ln -s "${PREFIX}/lib" runtime-lib
./library-probe
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"
