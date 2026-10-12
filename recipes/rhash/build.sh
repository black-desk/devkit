#!/usr/bin/env bash
set -euxo pipefail
source "${SRC_DIR}/devkit-build/build-env.sh"
# The exact seed conda-forge recipe also disables the optional OpenSSL backend.
# Keep the built-in algorithms, shared/static libraries and command-line tool.
./configure --prefix="${PREFIX}" --cc="${CC}" --ar="${AR}" \
  --extra-cflags="${CFLAGS}" --extra-ldflags="${LDFLAGS} -Wl,-rpath,${SRC_DIR}/librhash" \
  --disable-openssl --enable-lib-static --enable-lib-shared
make -j"${CPU_COUNT}"
devkit_test make test-libs test-full
make install
make -C librhash install-lib-headers install-so-link
mkdir -p "${PREFIX}/lib/pkgconfig"
cp dist/librhash.pc "${PREFIX}/lib/pkgconfig/"
mkdir -p "${PREFIX}/include/rhash-${LIBRARY_VERSION}"
mv "${PREFIX}/include/"rhash*.h "${PREFIX}/include/rhash-${LIBRARY_VERSION}/"
python3 - <<'PYCONFIG'
import os
from pathlib import Path
p = Path(os.environ['PREFIX']) / 'lib/pkgconfig/librhash.pc'
s = p.read_text().splitlines()
s = ['prefix=${pcfiledir}/../..' if line.startswith('prefix=') else
     'exec_prefix=${prefix}' if line.startswith('exec_prefix=') else
     'libdir=${prefix}/lib' if line.startswith('libdir=') else
     'includedir=${prefix}/include/rhash-' + os.environ['LIBRARY_VERSION']
     if line.startswith('includedir=') else line for line in s]
p.write_text(('\n'.join(s) + '\n').replace('-L${libdir} -lrhash', '${libdir}/librhash.so'))
PYCONFIG
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"
