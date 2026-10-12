#!/usr/bin/env bash
set -euxo pipefail
source "${SRC_DIR}/devkit-build/build-env.sh"
export LDFLAGS="${LDFLAGS} -L${PREFIX}/lib/llvm-runtime -lgcc_s"
cp "${BUILD_PREFIX}/share/gnuconfig/config.guess" build-aux/config.guess
cp "${BUILD_PREFIX}/share/gnuconfig/config.sub" build-aux/config.sub
# Preserve conda-forge's default codec/filter/threading configuration.
./configure --prefix="${PREFIX}"
make -j"${CPU_COUNT}"
devkit_test make check
# This seed dependency is the library; test the tools upstream but install
# only the library/development files in the channel package.
make -C src/liblzma install
mkdir -p "${PREFIX}/include/liblzma-${LIBRARY_VERSION}"
mv "${PREFIX}/include/lzma.h" "${PREFIX}/include/lzma" \
  "${PREFIX}/include/liblzma-${LIBRARY_VERSION}/"
sed -i "s|includedir=.*|includedir=\${prefix}/include/liblzma-${LIBRARY_VERSION}|" \
  "${PREFIX}/lib/pkgconfig/liblzma.pc"
rm -f "${PREFIX}/lib/liblzma.la"
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"
