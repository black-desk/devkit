#!/usr/bin/env bash
set -euxo pipefail
source "${SRC_DIR}/devkit-build/build-env.sh"
cp "${BUILD_PREFIX}/share/gnuconfig/"config.* src/config/
export PKG_CONFIG="${BUILD_PREFIX}/bin/pkgconf"
export PKG_CONFIG_LIBDIR="${PREFIX}/lib/pkgconfig"
unset PKG_CONFIG_PATH
export CPPFLAGS="${CPPFLAGS} -I${PREFIX}/include/openssl-3.5.9 -I${PREFIX}/include/keyutils-1.6.3"
export LDFLAGS="${LDFLAGS} -L${PREFIX}/lib/llvm-runtime -lgcc_s -Wl,-rpath,${SRC_DIR}/src/lib"
cd src
# MIT's official release includes configure; unlike the Git snapshot used by
# forge, it does not require autoreconf. Keep forge's native feature baseline.
# Explicit NLS makes a missing msgfmt an error instead of silently dropping it.
./configure --prefix="${PREFIX}" --includedir="${PREFIX}/include/krb5-${LIBRARY_VERSION}" \
  --without-tcl --without-readline --with-libedit --with-crypto-impl=openssl \
  --with-keyutils=yes --without-system-verto --enable-nls
make -j"${CPU_COUNT}"
make install
cd ..
"${CC}" ${CFLAGS} ${LDFLAGS} -I"${PREFIX}/include/krb5-${LIBRARY_VERSION}" \
  "${RECIPE_DIR}/tests/probe.c" "${PREFIX}/lib/libkrb5.so" \
  '-Wl,--enable-new-dtags,-rpath,$ORIGIN/runtime-lib' -o library-probe
mkdir runtime-lib
ln -s "${PREFIX}/lib/libkrb5.so.3" runtime-lib/libkrb5.so.3
./library-probe
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"
