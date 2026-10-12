#!/usr/bin/env bash
set -euxo pipefail
source "${SRC_DIR}/devkit-build/build-env.sh"
export CFLAGS="${CFLAGS} -Wall -Winline -D_FILE_OFFSET_BITS=64"
# Build libraries/tools separately from the upstream fixture target.
make -j"${CPU_COUNT}" CC="${CC}" AR="${AR}" RANLIB="${RANLIB}" \
  CFLAGS="${CFLAGS}" LDFLAGS="${LDFLAGS}" libbz2.a bzip2 bzip2recover
devkit_test make test CC="${CC}" AR="${AR}" RANLIB="${RANLIB}" \
  CFLAGS="${CFLAGS}" LDFLAGS="${LDFLAGS}"
make install PREFIX="${PREFIX}" CC="${CC}" AR="${AR}" RANLIB="${RANLIB}" \
  CFLAGS="${CFLAGS}" LDFLAGS="${LDFLAGS}"
make -f Makefile-libbz2_so -j"${CPU_COUNT}" CC="${CC}" \
  CFLAGS="${CFLAGS}" LDFLAGS="${LDFLAGS} -Wl,-rpath,${SRC_DIR}"
cp -a libbz2.so.1.0.8 libbz2.so.1.0 "${PREFIX}/lib/"
ln -s libbz2.so.1.0 "${PREFIX}/lib/libbz2.so"
# Exercise the shared-library executable before package relocation.
./bzip2-shared -dc sample1.bz2 > shared-result
cmp sample1.ref shared-result
mkdir -p "${PREFIX}/include/bzip2-${LIBRARY_VERSION}" "${PREFIX}/share/man"
mv "${PREFIX}/include/bzlib.h" "${PREFIX}/include/bzip2-${LIBRARY_VERSION}/"
mv "${PREFIX}/man/"* "${PREFIX}/share/man/"
rmdir "${PREFIX}/man"
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"
