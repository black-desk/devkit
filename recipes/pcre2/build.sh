#!/usr/bin/env bash
set -euxo pipefail

: "${PCRE2_VERSION:?rattler-build must provide PCRE2_VERSION}"
: "${SYSROOT_TRIPLET:?rattler-build must provide SYSROOT_TRIPLET}"

: "${BUILD_PREFIX:?}"
: "${PREFIX:?}"
export SYSROOT="${BUILD_PREFIX}/${SYSROOT_TRIPLET:-x86_64-pc-linux-gnu}/sysroot"
export CC="${BUILD_PREFIX}/bin/clang"
export CXX="${BUILD_PREFIX}/bin/clang++"
DEVKIT_FLAGS="--no-default-config --config=${BUILD_PREFIX}/share/devkit/clang.cfg"
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
export CXXFLAGS="${CFLAGS}"
export CPPFLAGS="${DEVKIT_FLAGS}"
export LDFLAGS="${DEVKIT_FLAGS} --ld-path=${BUILD_PREFIX}/bin/ld.lld -L${PREFIX}/lib/devkit/lib -L${PREFIX}/lib -Wl,-rpath-link,${PREFIX}/lib"
test -d "${SYSROOT}"
test -x "${CC}"

# Match forge's complete interfaces and use upstream's relocatable CMake exports.
# libedit supplies pcre2test's readline interface without another readline library.
cmake -S . -B build -G Ninja \
  -DCMAKE_PREFIX_PATH="${PREFIX}/lib/devkit" \
  -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=OFF \
  '-DCMAKE_INSTALL_RPATH=$ORIGIN:$ORIGIN/../lib' \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_INSTALL_LIBDIR=lib \
  -DCMAKE_INSTALL_INCLUDEDIR="lib/devkit/include/pcre2-${PCRE2_VERSION}" \
  -DCMAKE_C_COMPILER="${CC}" \
  -DCMAKE_C_FLAGS="${CFLAGS} -O3" \
  -DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}" \
  -DCMAKE_SHARED_LINKER_FLAGS="${LDFLAGS}" \
  -DCMAKE_BUILD_RPATH="${PREFIX}/lib" \
  -DCMAKE_FIND_ROOT_PATH="${PREFIX};${SYSROOT}" \
  -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
  -DCMAKE_DISABLE_FIND_PACKAGE_Readline=ON \
  -DBUILD_SHARED_LIBS=ON -DBUILD_STATIC_LIBS=ON \
  -DPCRE2_BUILD_PCRE2_8=ON -DPCRE2_BUILD_PCRE2_16=ON -DPCRE2_BUILD_PCRE2_32=ON \
  -DPCRE2_SUPPORT_JIT=ON -DPCRE2_SUPPORT_UNICODE=ON \
  -DPCRE2_BUILD_PCRE2GREP=ON -DPCRE2_BUILD_TESTS=ON \
  -DPCRE2_SUPPORT_LIBZ=ON -DPCRE2_SUPPORT_LIBBZ2=ON \
  -DPCRE2_SUPPORT_LIBEDIT=ON -DPCRE2_SUPPORT_LIBREADLINE=OFF \
  -DZLIB_INCLUDE_DIR="${PREFIX}/lib/devkit/include/zlib-1.3.2" \
  -DZLIB_LIBRARY="${PREFIX}/lib/devkit/lib/libz.so" \
  -DBZIP2_INCLUDE_DIR="${PREFIX}/lib/devkit/include/bzip2-1.0.8" \
  -DBZIP2_LIBRARY_RELEASE="${PREFIX}/lib/devkit/lib/libbz2.so" \
  -DEDITLINE_INCLUDE_DIR="${PREFIX}/lib/devkit/include/libedit-3.1.20260512/editline" \
  -DEDITLINE_LIBRARY="${PREFIX}/lib/devkit/lib/libedit.so"
cmake --build build --parallel "${CPU_COUNT}"
ctest --test-dir build --output-on-failure --parallel "${CPU_COUNT}"
cmake --install build

cat >"${SRC_DIR}/devkit-consumer.c" <<'EOF'
#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>

#include <stdio.h>

int main(void) {
  int error_code;
  PCRE2_SIZE error_offset;
  pcre2_code *code = pcre2_compile(
    (PCRE2_SPTR)"devkit", PCRE2_ZERO_TERMINATED, 0,
    &error_code, &error_offset, NULL
  );
  if (code == NULL) {
    return 1;
  }
  pcre2_code_free(code);
  puts("pcre2");
  return 0;
}
EOF

"${CC}" \
  ${CFLAGS} ${LDFLAGS} -Wl,-rpath,"${PREFIX}/lib" \
  -I"${PREFIX}/lib/devkit/include/pcre2-${PCRE2_VERSION}" \
  "${SRC_DIR}/devkit-consumer.c" \
  "${PREFIX}/lib/libpcre2-8.so" \
  -o "${SRC_DIR}/devkit-consumer"

env -u LD_LIBRARY_PATH -u LD_PRELOAD "${SRC_DIR}/devkit-consumer"

# Stage only this package's development interfaces; preserve runtime libraries.
python3 "${BUILD_PREFIX}/share/devkit/stage-development.py" "${PREFIX}" --all
