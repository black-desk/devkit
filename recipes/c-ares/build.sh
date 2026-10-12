#!/usr/bin/env bash
set -euxo pipefail
source "${SRC_DIR}/devkit-build/build-env.sh"
# Match the seed's threaded shared/tool configuration; also retain static content.
# The seed does not enable the GoogleTest-dependent upstream test executable.
cmake -S . -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_INSTALL_INCLUDEDIR="include/c-ares-${LIBRARY_VERSION}" \
  -DCMAKE_C_COMPILER="${CC}" -DCMAKE_C_FLAGS="${CFLAGS}" \
  -DCMAKE_AR="${AR}" -DCMAKE_RANLIB="${RANLIB}" \
  -DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}" -DCMAKE_SHARED_LINKER_FLAGS="${LDFLAGS}" \
  '-DCMAKE_INSTALL_RPATH=$ORIGIN:$ORIGIN/../lib' \
  -DCARES_SHARED=ON -DCARES_STATIC=ON -DCARES_STATIC_PIC=ON -DCARES_THREADS=ON
cmake --build build --parallel "${CPU_COUNT}"
cmake --install build
python3 - <<'PY'
import os
from pathlib import Path
p = Path(os.environ['PREFIX']) / 'lib/pkgconfig/libcares.pc'
lines = p.read_text().splitlines()
lines = ['prefix=${pcfiledir}/../..' if x.startswith('prefix=') else
         'exec_prefix=${prefix}' if x.startswith('exec_prefix=') else
         'libdir=${prefix}/lib' if x.startswith('libdir=') else
         'includedir=${prefix}/include/c-ares-' + os.environ['LIBRARY_VERSION']
         if x.startswith('includedir=') else x for x in lines]
p.write_text(('\n'.join(lines) + '\n').replace('-L${libdir} -lcares', '${libdir}/libcares.so'))
PY
"${CC}" ${CFLAGS} ${LDFLAGS} -I"${PREFIX}/include/c-ares-${LIBRARY_VERSION}" \
  "${RECIPE_DIR}/tests/probe.c" "${PREFIX}/lib/libcares.so" \
  '-Wl,--enable-new-dtags,-rpath,$ORIGIN/runtime-lib' -o library-probe
mkdir runtime-lib
ln -s "${PREFIX}/lib/libcares.so.2" runtime-lib/libcares.so.2
./library-probe
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"
