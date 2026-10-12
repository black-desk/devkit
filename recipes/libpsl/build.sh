#!/usr/bin/env bash
set -euxo pipefail

# Bootstrap skips suites in dirty/result; standalone builds run them by default.
case "${DEVKIT_RUN_TESTS:-1}" in
  0|1) ;;
  *) printf 'error: DEVKIT_RUN_TESTS must be 0 or 1\n' >&2; exit 1 ;;
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
  export CXXFLAGS="${CFLAGS} --start-no-unused-arguments -stdlib=libc++ -nostdinc++ -isystem ${PREFIX}/include/libcxx-23.1.3/c++/v1 --end-no-unused-arguments"
else
  # clang.cfg already selects libc++ headers. Adding a second copy from the
  # native host prefix breaks C wrapper include_next. Both prefixes select
  # the same libc++ package from the completed input generation.
  export CXXFLAGS="${CFLAGS}"
fi
export CPPFLAGS="${DEVKIT_FLAGS}"
export LDFLAGS="${DEVKIT_FLAGS} --ld-path=${BUILD_PREFIX}/bin/ld.lld -L${PREFIX}/lib -Wl,-rpath-link,${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib"
test -d "${SYSROOT}"
test -x "${CC}"
cp "${BUILD_PREFIX}/share/gnuconfig/"config.* .
export PKG_CONFIG="${BUILD_PREFIX}/bin/pkgconf"
export PKG_CONFIG_LIBDIR="${PREFIX}/lib/pkgconfig"
unset PKG_CONFIG_PATH PYTHON
export CPPFLAGS="${CPPFLAGS} $(${PKG_CONFIG} --cflags icu-uc)"
export LDFLAGS="${LDFLAGS} -Wl,-rpath,${SRC_DIR}/src/.libs"
# The release contains these generated files. Upstream configure explicitly
# requires Python only if any are absent; keep all built-in data and tests.
test -f src/suffixes_dafsa.h
test -f tests/psl.dafsa
test -f tests/psl_ascii.dafsa
./configure --prefix="${PREFIX}" --includedir="${PREFIX}/include/libpsl-${LIBRARY_VERSION}" \
  --enable-runtime=libicu --enable-builtin --disable-static
make -j"${CPU_COUNT}" AM_LDFLAGS=-no-install
if [[ "${DEVKIT_RUN_TESTS:-1}" == 1 ]]; then
  make check AM_LDFLAGS=-no-install
fi
make install AM_LDFLAGS=-no-install
rm -f "${PREFIX}/lib/libpsl.la"
# The seed carrier excludes this Python data-regeneration helper too.
# Retain the compiled library, built-in data and native psl command.
rm -f "${PREFIX}/bin/psl-make-dafsa" "${PREFIX}/share/man/man1/psl-make-dafsa.1"
python3 - <<'PY'
import os
from pathlib import Path
p = Path(os.environ['PREFIX']) / 'lib/pkgconfig/libpsl.pc'
lines = p.read_text().splitlines()
lines = ['prefix=${pcfiledir}/../..' if x.startswith('prefix=') else
         'exec_prefix=${prefix}' if x.startswith('exec_prefix=') else
         'libdir=${prefix}/lib' if x.startswith('libdir=') else
         'includedir=${prefix}/include/libpsl-' + os.environ['LIBRARY_VERSION']
         if x.startswith('includedir=') else x for x in lines]
p.write_text(('\n'.join(lines) + '\n').replace('-L${libdir} -lpsl', '${libdir}/libpsl.so'))
PY
"${CC}" ${CFLAGS} ${LDFLAGS} -I"${PREFIX}/include/libpsl-${LIBRARY_VERSION}" \
  "${RECIPE_DIR}/tests/probe.c" "${PREFIX}/lib/libpsl.so" \
  '-Wl,--enable-new-dtags,-rpath,$ORIGIN/runtime-lib' -o library-probe
mkdir runtime-lib
ln -s "${PREFIX}/lib/libpsl.so.5" runtime-lib/libpsl.so.5
./library-probe
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"
