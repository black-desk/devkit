#!/usr/bin/env bash
set -euxo pipefail
source "${SRC_DIR}/devkit-build/build-env.sh"
cp "${BUILD_PREFIX}/share/gnuconfig/"config.* .
./configure --prefix="${PREFIX}" --includedir="${PREFIX}/include/libev-${LIBRARY_VERSION}"
make -j"${CPU_COUNT}"
devkit_test make check
make install
# All three headers, including the compatibility interface, stay version-isolated.
"${CC}" ${CFLAGS} ${LDFLAGS} -I"${PREFIX}/include/libev-${LIBRARY_VERSION}" \
  "${RECIPE_DIR}/tests/probe.c" "${PREFIX}/lib/libev.so" \
  '-Wl,--enable-new-dtags,-rpath,$ORIGIN/runtime-lib' -o library-probe
mkdir runtime-lib
ln -s "${PREFIX}/lib/libev.so.4" runtime-lib/libev.so.4
./library-probe
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"
