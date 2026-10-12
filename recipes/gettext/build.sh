#!/usr/bin/env bash
set -euxo pipefail
source "${SRC_DIR}/devkit-build/build-env.sh"
cp "${BUILD_PREFIX}/share/gnuconfig/"config.* build-aux/
export CPP="${CC} -E"
export CPPFLAGS="${CPPFLAGS} -I${PREFIX}/include/libiconv-1.18 -I${PREFIX}/include/ncurses-6.6"
export CXXFLAGS="${CXXFLAGS} -I${PREFIX}/include/libiconv-1.18"
export LDFLAGS="${LDFLAGS} -L${PREFIX}/lib/llvm-runtime -lgcc_s -Wl,-rpath,${SRC_DIR}/gettext-tools/src/.libs -Wl,-rpath,${SRC_DIR}/gettext-runtime/intl/.libs -Wl,-rpath,${SRC_DIR}/gettext-runtime/libasprintf/.libs -Wl,-rpath,${SRC_DIR}/libtextstyle/lib/.libs"
# Match conda-forge 0.25.1's native tool/library feature configuration.
# Release scripts and parsers are pre-generated; no autoreconf is required.
./configure --prefix="${PREFIX}" --includedir="${PREFIX}/include/gettext-${LIBRARY_VERSION}" \
  --with-libiconv-prefix="${PREFIX}" --disable-static --disable-csharp \
  --disable-dependency-tracking --disable-java --disable-native-java \
  --disable-openmp --enable-fast-install --without-emacs
make -j"${CPU_COUNT}" AM_LDFLAGS=-no-install
# The build already embeds build-tree RUNPATH. Do not propagate the Libtool-only
# option into autopoint's generated ordinary C example through MAKEFLAGS.
devkit_test make check
make install AM_LDFLAGS=-no-install
rm -f "${PREFIX}/share/info/dir"
find "${PREFIX}" -name '*.la' -delete
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"
