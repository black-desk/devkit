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
unset LD_LIBRARY_PATH LD_PRELOAD
unset PYTHON
export CPPFLAGS="${CPPFLAGS} -I${PREFIX}/lib/devkit/include/libiconv-1.18 -I${PREFIX}/lib/devkit/include/zlib-1.3.2"
export LDFLAGS="${LDFLAGS} -lgcc_s -liconv -Wl,-rpath,${SRC_DIR}/.libs"
export PKG_CONFIG="${BUILD_PREFIX}/bin/pkgconf"
export PKG_CONFIG_LIBDIR="${PREFIX}/lib/devkit/lib/pkgconfig"
unset PKG_CONFIG_PATH
# Libtool drops a bare absolute .so from libxml2_la_LIBADD. Preserve the exact
# pkg-config-selected zlib through the linker, as the curl recipe does for DSOs.
# TODO: upstream support for absolute shared-library inputs in GNU Libtool.
export Z_LIBS="-Wl,${PREFIX}/lib/devkit/lib/libz.so"
cp "${BUILD_PREFIX}/share/gnuconfig/config.guess" config.guess
cp "${BUILD_PREFIX}/share/gnuconfig/config.sub" config.sub
# FTP and LZMA were removed upstream before/in 2.15; the forge recipe's old
# options no longer enable them. --with-tls means thread-local storage.
./configure --prefix="${PREFIX}" --includedir="${PREFIX}/lib/devkit/include/libxml2-${LIBRARY_VERSION}" --with-iconv --with-zlib --with-icu \
  --with-legacy --with-python=no --with-tls --enable-static=no \
  --with-schematron=yes
# Libtool's -no-install builds executables with build-tree RUNPATH instead of
# loader-environment shell wrappers. Finalization replaces that RUNPATH.
make -j"${CPU_COUNT}" AM_LDFLAGS=-no-install
if [[ "${DEVKIT_RUN_TESTS:-1}" == 1 ]]; then
  make check AM_LDFLAGS=-no-install
fi
make install AM_LDFLAGS=-no-install \
  pkgconfigdir="${PREFIX}/lib/devkit/lib/pkgconfig" \
  cmakedir="${PREFIX}/lib/devkit/lib/cmake/libxml2"
rm -f "${PREFIX}/lib/libxml2.la"
# Post-link exception: Libtool -no-install avoids global loader wrappers for upstream tests but installs build-tree RUNPATH unchanged.
# TODO: replace with target-specific upstream install/relink support.
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"

# Stage this package's development files after the build-tree consumer tests.
python3 "${SRC_DIR}/devkit-build/stage-development.py" "${PREFIX}" --all
