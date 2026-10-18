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
export LDFLAGS="${DEVKIT_FLAGS} --ld-path=${BUILD_PREFIX}/bin/ld.lld -L${PREFIX}/lib/devkit/lib -Wl,-rpath-link,${PREFIX}/lib/devkit/lib"
test -d "${SYSROOT}"
test -x "${CC}"

# Upstream CMake installs CONFIG exports as well as pkg-config metadata.
# Keep build/test RUNPATH on runtime directories; install relative RUNPATH.
cmake -S "${SRC_DIR}" -B "${SRC_DIR}/build" -G Ninja \
  -DCMAKE_PREFIX_PATH="${PREFIX}/lib/devkit" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_INSTALL_DATAROOTDIR=lib/devkit/share \
  -DCMAKE_INSTALL_LIBEXECDIR=lib/devkit/libexec \
  -DCMAKE_INSTALL_LIBDIR=lib/devkit/lib \
  -DCMAKE_INSTALL_INCLUDEDIR="lib/devkit/include/zlib-${ZLIB_VERSION}" \
  -DCMAKE_C_COMPILER="${CC}" -DCMAKE_C_FLAGS="${CFLAGS}" \
  -DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}" \
  -DCMAKE_SHARED_LINKER_FLAGS="${LDFLAGS}" \
  -DCMAKE_BUILD_RPATH="${PREFIX}/lib/devkit/lib" \
  '-DCMAKE_INSTALL_RPATH=$ORIGIN:$ORIGIN/../lib/devkit/lib' \
  -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=OFF \
  -DZLIB_BUILD_SHARED=ON -DZLIB_BUILD_STATIC=ON -DZLIB_BUILD_TESTING=ON
cmake --build "${SRC_DIR}/build" --parallel "${CPU_COUNT}"
if [[ "${DEVKIT_RUN_TESTS:-1}" == 1 ]]; then
  ctest --test-dir "${SRC_DIR}/build" --output-on-failure --parallel "${CPU_COUNT}"
fi
cmake --install "${SRC_DIR}/build"
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
  ${CFLAGS} ${LDFLAGS} -Wl,-rpath,"${PREFIX}/lib/devkit/lib" \
  -I"${PREFIX}/lib/devkit/include/zlib-${ZLIB_VERSION}" \
  "${SRC_DIR}/devkit-consumer.c" \
  "${PREFIX}/lib/devkit/lib/libz.so" \
  -o "${SRC_DIR}/devkit-consumer"

env -u LD_LIBRARY_PATH -u LD_PRELOAD "${SRC_DIR}/devkit-consumer"

# Seed tools retain public-library RPATH. Only dirty supplies runtime SONAME
# aliases for them; result/selfhost install exclusively in the private libdir.
if [[ "${SYSROOT_TRIPLET:-}" == x86_64-conda-linux-gnu ]]; then
  for library in "${PREFIX}/lib/devkit/lib/"libz.so.*; do
    [[ -f "${library}" ]] || continue
    soname="$(readelf -d "${library}" | sed -n 's/.*(SONAME).*\[\(.*\)\].*/\1/p')"
    [[ -n "${soname}" && "${soname}" != */* ]] || continue
    ln -sfn "devkit/lib/${soname}" "${PREFIX}/lib/${soname}"
  done
fi
