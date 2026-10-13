#!/usr/bin/env bash
set -euxo pipefail

# Bootstrap skips suites in dirty/result; standalone builds run them by default.
case "${DEVKIT_RUN_TESTS:-1}" in
  0 | 1) ;;
  *)
    printf 'error: DEVKIT_RUN_TESTS must be 0 or 1\n' >&2
    exit 1
    ;;
esac
: "${BUILD_PREFIX:?}"
: "${PREFIX:?}"
export SYSROOT="${BUILD_PREFIX}/${SYSROOT_TRIPLET:-x86_64-pc-linux-gnu}/sysroot"
export CC="${BUILD_PREFIX}/bin/clang"
export CXX="${BUILD_PREFIX}/bin/clang++"
if [[ "${SYSROOT_TRIPLET:-}" == x86_64-conda-linux-gnu ]]; then
  # Prepare the fresh seed build environment with unversioned driver names.
  ln -sfn clang-23 "${BUILD_PREFIX}/bin/clang"
  ln -sfn clang++-23 "${BUILD_PREFIX}/bin/clang++"
  DEVKIT_FLAGS="--start-no-unused-arguments --no-default-config --sysroot=${SYSROOT} --gcc-install-dir=${BUILD_PREFIX}/lib/gcc/x86_64-conda-linux-gnu/16.2.0 --rtlib=compiler-rt --unwindlib=none --end-no-unused-arguments"
else
  DEVKIT_FLAGS="--no-default-config --config=${BUILD_PREFIX}/share/devkit/clang.cfg"
fi
export AR="${BUILD_PREFIX}/bin/llvm-ar"
export RANLIB="${BUILD_PREFIX}/bin/llvm-ranlib"
export NM="${BUILD_PREFIX}/bin/llvm-nm"
export STRIP="${BUILD_PREFIX}/bin/llvm-strip"
export OBJCOPY="${BUILD_PREFIX}/bin/llvm-objcopy"
export OBJDUMP="${BUILD_PREFIX}/bin/llvm-objdump"
export READELF="${BUILD_PREFIX}/bin/llvm-readelf"
export LD="${BUILD_PREFIX}/bin/ld.lld"
export PATH="${BUILD_PREFIX}/bin:${PATH}"
export CFLAGS="${DEVKIT_FLAGS} -O2 -fPIC"
if [[ "${SYSROOT_TRIPLET:-}" == x86_64-conda-linux-gnu ]]; then
  export CXXFLAGS="${CFLAGS} --start-no-unused-arguments -stdlib=libc++ -nostdinc++ -isystem ${PREFIX}/lib/devkit/include/libcxx-23.1.3/c++/v1 --end-no-unused-arguments"
else
  # clang.cfg already selects libc++ headers. Adding a second copy from the
  # native host prefix breaks C wrapper include_next. Both prefixes select
  # the same libc++ package from the completed input generation.
  export CXXFLAGS="${CFLAGS}"
fi
export CPPFLAGS="${DEVKIT_FLAGS}"
export LDFLAGS="${DEVKIT_FLAGS} --ld-path=${BUILD_PREFIX}/bin/ld.lld -L${PREFIX}/lib/devkit/lib -L${PREFIX}/lib -Wl,-rpath-link,${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib"
test -d "${SYSROOT}"
test -x "${CC}"
cp "${BUILD_PREFIX}/share/gnuconfig/"config.* build-aux/
export CPP="${CC} -E"
export CPPFLAGS="${CPPFLAGS} -I${PREFIX}/lib/devkit/include/libiconv-1.18 -I${PREFIX}/lib/devkit/include/ncurses-6.6"
export CXXFLAGS="${CXXFLAGS} -I${PREFIX}/lib/devkit/include/libiconv-1.18"
export LDFLAGS="${LDFLAGS} -L${PREFIX}/lib/devkit/lib/llvm-runtime -lgcc_s -Wl,-rpath,${SRC_DIR}/gettext-tools/src/.libs -Wl,-rpath,${SRC_DIR}/gettext-runtime/intl/.libs -Wl,-rpath,${SRC_DIR}/gettext-runtime/libasprintf/.libs -Wl,-rpath,${SRC_DIR}/libtextstyle/lib/.libs"
# Match conda-forge 0.25.1's native tool/library feature configuration.
# Release scripts and parsers are pre-generated; no autoreconf is required.
./configure --prefix="${PREFIX}" --includedir="${PREFIX}/include/gettext-${LIBRARY_VERSION}" \
  --with-libiconv-prefix="${PREFIX}/lib/devkit" --disable-static --disable-csharp \
  --disable-dependency-tracking --disable-java --disable-native-java \
  --disable-openmp --enable-fast-install --without-emacs
make -j"${CPU_COUNT}" AM_LDFLAGS=-no-install
# The build already embeds build-tree RUNPATH. Do not propagate the Libtool-only
# option into autopoint's generated ordinary C example through MAKEFLAGS.
if [[ "${DEVKIT_RUN_TESTS:-1}" == 1 ]]; then
  make check
fi
make install AM_LDFLAGS=-no-install
rm -f "${PREFIX}/share/info/dir"
find "${PREFIX}" -name '*.la' -delete
# Post-link exception: Libtool -no-install is needed by in-tree tools; installed gettext/libtextstyle programs retain build-tree paths.
# TODO: replace with target-specific upstream install/relink support.
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"

# Stage only this package's development interfaces; preserve runtime libraries.
python3 "${SRC_DIR}/devkit-build/stage-development.py" "${PREFIX}" --all \
  --runtime-library "libgettextlib-${LIBRARY_VERSION}.so" \
  --runtime-library "libgettextsrc-${LIBRARY_VERSION}.so"
