#!/usr/bin/env bash
set -euxo pipefail

# Bootstrap skips suites in dirty/result; standalone builds run them by default.
case "${DEVKIT_RUN_TESTS:-1}" in
  0|1) ;;
  *) printf 'error: DEVKIT_RUN_TESTS must be 0 or 1\n' >&2; exit 1 ;;
esac

: "${ZLIB_VERSION:?rattler-build must provide ZLIB_VERSION}"
: "${SYSROOT_TRIPLET:?rattler-build must provide SYSROOT_TRIPLET}"

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

# TODO: Remove this recipe-local workaround when zlib fixes its shared-library
# configure probe, which applies zlib.map to an object lacking its symbols.
# Follow the workaround merged in https://github.com/NixOS/nixpkgs/pull/307540.
# Upstream: https://github.com/madler/zlib/issues/960
# Upstream: https://github.com/madler/zlib/issues/1318
export LDFLAGS="${LDFLAGS} -Wl,--undefined-version"

BUILD_DIR="${SRC_DIR}/build"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

../configure \
  --prefix="${PREFIX}" \
  --libdir="${PREFIX}/lib" \
  --includedir="${PREFIX}/include/zlib-${ZLIB_VERSION}"

make -j"${CPU_COUNT}"
if [[ "${DEVKIT_RUN_TESTS:-1}" == 1 ]]; then
  make test
fi
make install

cat >"${PREFIX}/lib/pkgconfig/zlib.pc" <<EOF
prefix=\${pcfiledir}/../..
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: zlib
Description: zlib compression library
Version: ${ZLIB_VERSION}
License: Zlib
Cflags: -I\${includedir}/zlib-${ZLIB_VERSION}
Libs: \${libdir}/libz.so
EOF

cat >"${SRC_DIR}/devkit-consumer.c" <<'EOF'
#include <zlib.h>

#include <stdio.h>

int main(void) {
  z_stream stream = {0};
  if (deflateInit(&stream, 1) != Z_OK) {
    return 1;
  }
  printf("%s\n", zlibVersion());
  deflateEnd(&stream);
  return 0;
}
EOF

"${CC}" \
  ${CFLAGS} ${LDFLAGS} \
  -I"${PREFIX}/include/zlib-${ZLIB_VERSION}" \
  "${SRC_DIR}/devkit-consumer.c" \
  "${PREFIX}/lib/libz.so" \
  -o "${SRC_DIR}/devkit-consumer"

env -u LD_LIBRARY_PATH -u LD_PRELOAD "${SRC_DIR}/devkit-consumer"

python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"
