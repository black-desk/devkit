#!/usr/bin/env bash
set -euxo pipefail
source "${SRC_DIR}/devkit-build/build-env.sh"
export LDFLAGS="${LDFLAGS} -L${PREFIX}/lib/llvm-runtime -lgcc_s"
for directory in build-aux libcharset/build-aux; do
  cp "${BUILD_PREFIX}/share/gnuconfig/config.guess" "${directory}/config.guess"
  cp "${BUILD_PREFIX}/share/gnuconfig/config.sub" "${directory}/config.sub"
done
./configure --prefix="${PREFIX}" --enable-static --disable-rpath \
  --enable-extra-encodings
make -j"${CPU_COUNT}"
make check
# Match conda-forge's library package: retain all encodings and static libraries,
# install library headers only, without the separately licensed CLI/docs.
make install-lib libdir="${PREFIX}/lib" includedir="${PREFIX}/include/libiconv-1.18"
make -C libcharset install-lib libdir="${PREFIX}/lib" \
  includedir="${PREFIX}/include/libiconv-1.18"
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"
