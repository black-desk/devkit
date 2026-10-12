#!/usr/bin/env bash
set -euxo pipefail
source "${SRC_DIR}/devkit-build/build-env.sh"
cp "${BUILD_PREFIX}/share/gnuconfig/"config.* build-aux/m4-autogen/
export PERL="${BUILD_PREFIX}/bin/perl"
test -x "${PERL}"
# Match conda-forge's main libxcrypt output; libcrypt.so.1 is a separate ABI.
./configure --prefix="${PREFIX}" \
  --includedir="${PREFIX}/include/libxcrypt-${LIBRARY_VERSION}" \
  --disable-static --enable-hashes=strong,glibc \
  --enable-obsolete-api=no --disable-failure-tokens
make -j"${CPU_COUNT}"
devkit_test make check -j"${CPU_COUNT}"
make install -j"${CPU_COUNT}"
rm -f "${PREFIX}/lib/libcrypt.la"
"${CC}" ${CFLAGS} ${LDFLAGS} -I"${PREFIX}/include/libxcrypt-${LIBRARY_VERSION}" \
  "${RECIPE_DIR}/tests/probe.c" "${PREFIX}/lib/libcrypt.so" \
  '-Wl,--enable-new-dtags,-rpath,$ORIGIN/runtime-lib' -o library-probe
ln -s "${PREFIX}/lib" runtime-lib
./library-probe
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"
