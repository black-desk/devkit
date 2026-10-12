#!/usr/bin/env bash
set -euxo pipefail
source "${SRC_DIR}/devkit-build/build-env.sh"
export PKG_CONFIG="${BUILD_PREFIX}/bin/pkgconf"
export PKG_CONFIG_LIBDIR="${PREFIX}/lib/pkgconfig"
unset PKG_CONFIG_PATH
cmake -S . -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_INSTALL_INCLUDEDIR="include/libarchive-${LIBRARY_VERSION}" \
  -DCMAKE_C_COMPILER="${CC}" -DCMAKE_C_FLAGS="${CFLAGS}" \
  -DCMAKE_AR="${AR}" -DCMAKE_RANLIB="${RANLIB}" \
  -DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}" -DCMAKE_SHARED_LINKER_FLAGS="${LDFLAGS}" \
  '-DCMAKE_INSTALL_RPATH=$ORIGIN:$ORIGIN/../lib' \
  -DCMAKE_FIND_ROOT_PATH="${SYSROOT};${PREFIX}" \
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
  -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
  -DENABLE_TEST=ON -DENABLE_LZO=ON -DENABLE_LZ4=ON -DENABLE_LZMA=ON \
  -DENABLE_ZSTD=ON -DENABLE_ZLIB=ON -DENABLE_BZip2=ON -DENABLE_OPENSSL=ON \
  -DENABLE_LIBXML2=ON -DENABLE_EXPAT=OFF -DENABLE_NETTLE=OFF -DENABLE_CNG=OFF \
  -DENABLE_ICONV=ON \
  -DICONV_INCLUDE_DIR="${PREFIX}/include/libiconv-1.18" -DLIBICONV_PATH="${PREFIX}/lib/libiconv.so" \
  -DZLIB_INCLUDE_DIR="${PREFIX}/include/zlib-1.3.2" -DZLIB_LIBRARY="${PREFIX}/lib/libz.so" \
  -DBZIP2_INCLUDE_DIR="${PREFIX}/include/bzip2-1.0.8" -DBZIP2_LIBRARY_RELEASE="${PREFIX}/lib/libbz2.so" \
  -DLIBLZMA_INCLUDE_DIR="${PREFIX}/include/liblzma-5.8.3" -DLIBLZMA_LIBRARY="${PREFIX}/lib/liblzma.so" \
  -DLZO2_INCLUDE_DIR="${PREFIX}/include/lzo-2.10" -DLZO2_LIBRARY="${PREFIX}/lib/liblzo2.so" \
  -DLZ4_INCLUDE_DIR="${PREFIX}/include/lz4-1.10.0" -DLZ4_LIBRARY="${PREFIX}/lib/liblz4.so" \
  -DZSTD_INCLUDE_DIR="${PREFIX}/include/zstd-1.5.7" -DZSTD_LIBRARY="${PREFIX}/lib/libzstd.so" \
  -DOPENSSL_INCLUDE_DIR="${PREFIX}/include/openssl-3.5.9" \
  -DOPENSSL_CRYPTO_LIBRARY="${PREFIX}/lib/libcrypto.so" -DOPENSSL_SSL_LIBRARY="${PREFIX}/lib/libssl.so" \
  -DLIBXML2_INCLUDE_DIR="${PREFIX}/include/libxml2-2.15.4" -DLIBXML2_LIBRARY="${PREFIX}/lib/libxml2.so"
# CMake requires iconv for the libxml2 backend, unlike the forge Autotools
# configuration. Use the existing channel libiconv to preserve XML support.
# Expat and Nettle remain disabled as in forge; retain the GPL/LZO backends.
for feature in HAVE_LIBLZO2 HAVE_LIBLZ4 HAVE_LIBLZMA HAVE_LIBZSTD HAVE_LIBZ HAVE_LIBBZ2 HAVE_LIBXML2; do
  grep -q "^#define ${feature} 1" build/config.h
 done
cmake --build build --parallel "${CPU_COUNT}"
devkit_test ctest --test-dir build --output-on-failure --parallel "${CPU_COUNT}"
cmake --install build
python3 - <<'PY'
import os
from pathlib import Path
p = Path(os.environ['PREFIX']) / 'lib/pkgconfig/libarchive.pc'
lines = p.read_text().splitlines()
backends = ['z', 'bz2', 'lzma', 'zstd', 'xml2', 'iconv', 'lzo2', 'lz4', 'crypto']
lines = ['prefix=${pcfiledir}/../..' if x.startswith('prefix=') else
         'exec_prefix=${prefix}' if x.startswith('exec_prefix=') else
         'libdir=${prefix}/lib' if x.startswith('libdir=') else
         'includedir=${prefix}/include/libarchive-' + os.environ['LIBRARY_VERSION']
         if x.startswith('includedir=') else
         'Libs: ${libdir}/libarchive.so' if x.startswith('Libs:') else
         'Libs.private: ' + ' '.join('${libdir}/lib'+n+'.so' for n in backends)
         if x.startswith('Libs.private:') else x for x in lines]
p.write_text('\n'.join(lines)+'\n')
PY
"${CC}" ${CFLAGS} ${LDFLAGS} -I"${PREFIX}/include/libarchive-${LIBRARY_VERSION}" \
  "${RECIPE_DIR}/tests/probe.c" "${PREFIX}/lib/libarchive.so" \
  '-Wl,--enable-new-dtags,-rpath,$ORIGIN/runtime-lib' -o library-probe
ln -s "${PREFIX}/lib" runtime-lib
./library-probe
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"
