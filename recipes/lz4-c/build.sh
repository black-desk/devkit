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
  DEVKIT_FLAGS="--no-default-config --config=${BUILD_PREFIX}/lib/devkit/share/devkit/clang.cfg"
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
# Make expands $$ once; shell quotes preserve the literal loader token.
export LDFLAGS="${DEVKIT_FLAGS} --ld-path=${BUILD_PREFIX}/bin/ld.lld -L${PREFIX}/lib/devkit/lib -Wl,-rpath-link,${PREFIX}/lib/devkit/lib"
test -d "${SYSROOT}"
test -x "${CC}"
# Keep flags in the environment: command-line LDFLAGS suppress upstream
# target-specific additions, including -pthread for the multithreaded CLI.
NATIVE_LDFLAGS="${LDFLAGS} -Wl,--enable-new-dtags,-rpath,'\$\$ORIGIN:\$\$ORIGIN/../lib/devkit/lib'"
LDFLAGS="${NATIVE_LDFLAGS}" make -j"${CPU_COUNT}" PREFIX="${PREFIX}" libdir="${PREFIX}/lib/devkit/lib" DATAROOTDIR="${PREFIX}/lib/devkit/share" INCLUDEDIR="${PREFIX}/lib/devkit/include/lz4-${LIBRARY_VERSION}"
if [[ "${DEVKIT_RUN_TESTS:-1}" == 1 ]]; then
  LDFLAGS="${NATIVE_LDFLAGS}" make -C tests datagen
  # Preserve conda-forge's corpus, including large and linked blocks.
  tests/datagen -g0 | ./lz4 -v | ./lz4 -t
  tests/datagen -g16KB | ./lz4 -9 | ./lz4 -t
  tests/datagen | ./lz4 | ./lz4 -t
  tests/datagen -g6M -P99 | ./lz4 -9BD | ./lz4 -t
  tests/datagen -g17M | ./lz4 -9v | ./lz4 -qt
  tests/datagen -g33M | ./lz4 --no-frame-crc | ./lz4 -t
  tests/datagen -g256MB | ./lz4 -vqB4D | ./lz4 -t
fi
LDFLAGS="${NATIVE_LDFLAGS}" make install PREFIX="${PREFIX}" libdir="${PREFIX}/lib/devkit/lib" DATAROOTDIR="${PREFIX}/lib/devkit/share" PKGCONFIGDIR="${PREFIX}/lib/devkit/lib/pkgconfig" INCLUDEDIR="${PREFIX}/lib/devkit/include/lz4-${LIBRARY_VERSION}"

# Seed tools retain public-library RPATH. Only dirty supplies runtime SONAME
# aliases for them; result/selfhost install exclusively in the private libdir.
if [[ "${SYSROOT_TRIPLET:-}" == x86_64-conda-linux-gnu ]]; then
  for library in "${PREFIX}/lib/devkit/lib/"liblz4.so.*; do
    [[ -f "${library}" ]] || continue
    soname="$(readelf -d "${library}" | sed -n 's/.*(SONAME).*\[\(.*\)\].*/\1/p')"
    [[ -n "${soname}" && "${soname}" != */* ]] || continue
    ln -sfn "devkit/lib/${soname}" "${PREFIX}/lib/${soname}"
  done
fi
