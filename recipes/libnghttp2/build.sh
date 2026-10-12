#!/usr/bin/env bash
set -euxo pipefail
source "${SRC_DIR}/devkit-build/build-env.sh"
cp "${BUILD_PREFIX}/share/gnuconfig/"config.* .
export PKG_CONFIG="${BUILD_PREFIX}/bin/pkgconf"
export PKG_CONFIG_LIBDIR="${PREFIX}/lib/pkgconfig"
unset PKG_CONFIG_PATH PYTHON
# AM_PATH_PYTHON's supported interpreter-absent branch is sufficient for release
# builds: installed man pages are shipped, Python only regenerates Sphinx API docs.
export am_cv_pathless_PYTHON=none
# configure clears CXXFLAGS during its C++20 probe. Keep standard-library
# selection on the compiler command so that this probe uses the same headers.
export CXX="${CXX} -stdlib=libc++ -nostdinc++ -isystem ${PREFIX}/include/libcxx-23.1.3/c++/v1"
export LIBEV_CFLAGS="-I${PREFIX}/include/libev-4.33"
export LIBEV_LIBS="${PREFIX}/lib/libev.so"
export LDFLAGS="${LDFLAGS} -L${PREFIX}/lib/llvm-runtime -lgcc_s -Wl,-rpath,${SRC_DIR}/lib/.libs"
# Preserve the seed's native applications and dependencies. Release scripts
# are pre-generated; Python bindings are absent from this upstream version.
./configure --prefix="${PREFIX}" \
  --includedir="${PREFIX}/include/libnghttp2-${LIBRARY_VERSION}" \
  --disable-static --enable-app --with-zlib --with-openssl --with-libev --with-libcares
make -j"${CPU_COUNT}" AM_LDFLAGS=-no-install
make check AM_LDFLAGS=-no-install
make install AM_LDFLAGS=-no-install
find "${PREFIX}" -name '*.la' -delete
python3 - <<'PY'
import os
from pathlib import Path
p = Path(os.environ['PREFIX']) / 'lib/pkgconfig/libnghttp2.pc'
lines = p.read_text().splitlines()
lines = ['prefix=${pcfiledir}/../..' if x.startswith('prefix=') else
         'exec_prefix=${prefix}' if x.startswith('exec_prefix=') else
         'libdir=${prefix}/lib' if x.startswith('libdir=') else
         'includedir=${prefix}/include/libnghttp2-' + os.environ['LIBRARY_VERSION']
         if x.startswith('includedir=') else x for x in lines]
p.write_text(('\n'.join(lines) + '\n').replace('-L${libdir} -lnghttp2', '${libdir}/libnghttp2.so'))
PY
"${CC}" ${CFLAGS} ${LDFLAGS} -I"${PREFIX}/include/libnghttp2-${LIBRARY_VERSION}" \
  "${RECIPE_DIR}/tests/probe.c" "${PREFIX}/lib/libnghttp2.so" \
  '-Wl,--enable-new-dtags,-rpath,$ORIGIN/runtime-lib' -o library-probe
mkdir runtime-lib
ln -s "${PREFIX}/lib/libnghttp2.so.14" runtime-lib/libnghttp2.so.14
./library-probe
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"
