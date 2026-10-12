#!/usr/bin/env bash
set -euxo pipefail
source "${SRC_DIR}/devkit-build/build-env.sh"
cmake -S . -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_INSTALL_INCLUDEDIR="include/libssh2-${LIBRARY_VERSION}" \
  -DCMAKE_C_COMPILER="${CC}" -DCMAKE_C_FLAGS="${CFLAGS}" \
  -DCMAKE_AR="${AR}" -DCMAKE_RANLIB="${RANLIB}" \
  -DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}" -DCMAKE_SHARED_LINKER_FLAGS="${LDFLAGS}" \
  '-DCMAKE_INSTALL_RPATH=$ORIGIN:$ORIGIN/../lib' -DCMAKE_BUILD_RPATH="${PREFIX}/lib" \
  -DBUILD_SHARED_LIBS=ON -DBUILD_STATIC_LIBS=OFF -DCRYPTO_BACKEND=OpenSSL \
  -DOPENSSL_INCLUDE_DIR="${PREFIX}/include/openssl-3.5.9" \
  -DOPENSSL_CRYPTO_LIBRARY="${PREFIX}/lib/libcrypto.so" \
  -DOPENSSL_SSL_LIBRARY="${PREFIX}/lib/libssl.so" \
  -DENABLE_ZLIB_COMPRESSION=ON -DZLIB_INCLUDE_DIR="${PREFIX}/include/zlib-1.3.2" \
  -DZLIB_LIBRARY="${PREFIX}/lib/libz.so" -DBUILD_TESTING=ON \
  -DRUN_DOCKER_TESTS=OFF -DRUN_SSHD_TESTS=OFF
# SSH-service integration tests are deferred until OpenSSH is packaged.
# Keep standalone tests enabled without depending on host sshd or Docker.
cmake --build build --parallel "${CPU_COUNT}"
ctest --test-dir build --output-on-failure
cmake --install build
python3 - <<'PY'
import os
from pathlib import Path
p = Path(os.environ['PREFIX']) / 'lib/pkgconfig/libssh2.pc'
lines = p.read_text().splitlines()
lines = ['prefix=${pcfiledir}/../..' if x.startswith('prefix=') else
         'exec_prefix=${prefix}' if x.startswith('exec_prefix=') else
         'libdir=${prefix}/lib' if x.startswith('libdir=') else
         'includedir=${prefix}/include/libssh2-' + os.environ['LIBRARY_VERSION']
         if x.startswith('includedir=') else x for x in lines]
p.write_text(('\n'.join(lines) + '\n').replace('-L${libdir} -lssh2', '${libdir}/libssh2.so'))
PY
"${CC}" ${CFLAGS} ${LDFLAGS} -I"${PREFIX}/include/libssh2-${LIBRARY_VERSION}" \
  "${RECIPE_DIR}/tests/probe.c" "${PREFIX}/lib/libssh2.so" \
  '-Wl,--enable-new-dtags,-rpath,$ORIGIN/runtime-lib' -o library-probe
mkdir runtime-lib
ln -s "${PREFIX}/lib/libssh2.so.1" runtime-lib/libssh2.so.1
./library-probe
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"
