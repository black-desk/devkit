#!/usr/bin/env bash
set -euxo pipefail
source "${SRC_DIR}/devkit-build/build-env.sh"
cmake -S . -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_INSTALL_INCLUDEDIR="include/libuv-${LIBRARY_VERSION}" \
  -DCMAKE_C_COMPILER="${CC}" -DCMAKE_C_FLAGS="${CFLAGS}" \
  -DCMAKE_AR="${AR}" -DCMAKE_RANLIB="${RANLIB}" \
  -DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}" -DCMAKE_SHARED_LINKER_FLAGS="${LDFLAGS}" \
  '-DCMAKE_INSTALL_RPATH=$ORIGIN' -DCMAKE_BUILD_RPATH="${PWD}/build;${PREFIX}/lib" \
  -DLIBUV_BUILD_SHARED=ON -DLIBUV_BUILD_TESTS=ON -DBUILD_TESTING=ON
cmake --build build --target uv uv_a uv_run_tests --parallel "${CPU_COUNT}"
# Run the full shared-library suite; tests run against the build-tree RUNPATH.
devkit_test ctest --test-dir build -R '^uv_test$' --output-on-failure
cmake --install build
python3 - <<'PY'
import os
from pathlib import Path
prefix = Path(os.environ['PREFIX'])
for path in (prefix / 'lib/pkgconfig').glob('libuv*.pc'):
    lines = path.read_text().splitlines()
    lines = ['prefix=${pcfiledir}/../..' if line.startswith('prefix=') else
             'libdir=${prefix}/lib' if line.startswith('libdir=') else
             'includedir=${prefix}/include/libuv-' + os.environ['LIBRARY_VERSION']
             if line.startswith('includedir=') else line for line in lines]
    text = '\n'.join(lines) + '\n'
    text = text.replace('-L${libdir} -l:libuv.a', '${libdir}/libuv.a')
    text = text.replace('-L${libdir} -luv', '${libdir}/libuv.so')
    path.write_text(text)
PY
"${CC}" ${CFLAGS} ${LDFLAGS} -I"${PREFIX}/include/libuv-${LIBRARY_VERSION}" \
  "${RECIPE_DIR}/tests/probe.c" "${PREFIX}/lib/libuv.so" \
  '-Wl,--enable-new-dtags,-rpath,$ORIGIN/runtime-lib' -o "${SRC_DIR}/uv-probe"
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"
