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
export LDFLAGS="${DEVKIT_FLAGS} --ld-path=${BUILD_PREFIX}/bin/ld.lld -L${PREFIX}/lib/devkit/lib -L${PREFIX}/lib -Wl,-rpath-link,${PREFIX}/lib"
test -d "${SYSROOT}"
test -x "${CC}"
export PKG_CONFIG="${BUILD_PREFIX}/bin/pkgconf"
export PKG_CONFIG_LIBDIR="${PREFIX}/lib/devkit/lib/pkgconfig"
unset PKG_CONFIG_PATH
cmake -S . -B build -G Ninja \
  -DCMAKE_PREFIX_PATH="${PREFIX}/lib/devkit" \
  -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=OFF \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_BUILD_RPATH="${PREFIX}/lib" \
  -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_INSTALL_INCLUDEDIR="lib/devkit/include/libarchive-${LIBRARY_VERSION}" \
  -DCMAKE_C_COMPILER="${CC}" -DCMAKE_C_FLAGS="${CFLAGS}" \
  -DCMAKE_AR="${AR}" -DCMAKE_RANLIB="${RANLIB}" \
  -DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}" -DCMAKE_SHARED_LINKER_FLAGS="${LDFLAGS}" \
  '-DCMAKE_INSTALL_RPATH=$ORIGIN:$ORIGIN/../lib' \
  -DCMAKE_FIND_ROOT_PATH="${SYSROOT};${PREFIX}" \
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
  -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
  -DENABLE_TEST=ON -DENABLE_LZO=ON -DENABLE_LZ4=ON -DENABLE_LZMA=ON \
  -DENABLE_ZSTD=ON -DENABLE_ZLIB=ON -DENABLE_BZip2=ON -DENABLE_OPENSSL=ON \
  -DENABLE_LIBXML2=ON -DENABLE_EXPAT=OFF -DENABLE_NETTLE=OFF -DENABLE_CNG=OFF \
  -DENABLE_ICONV=ON \
  -DICONV_INCLUDE_DIR="${PREFIX}/lib/devkit/include/libiconv-1.18" -DLIBICONV_PATH="${PREFIX}/lib/devkit/lib/libiconv.so" \
  -DZLIB_INCLUDE_DIR="${PREFIX}/lib/devkit/include/zlib-1.3.2" -DZLIB_LIBRARY="${PREFIX}/lib/devkit/lib/libz.so" \
  -DBZIP2_INCLUDE_DIR="${PREFIX}/lib/devkit/include/bzip2-1.0.8" -DBZIP2_LIBRARY_RELEASE="${PREFIX}/lib/devkit/lib/libbz2.so" \
  -DLIBLZMA_INCLUDE_DIR="${PREFIX}/lib/devkit/include/liblzma-5.8.3" -DLIBLZMA_LIBRARY="${PREFIX}/lib/devkit/lib/liblzma.so" \
  -DLZO2_INCLUDE_DIR="${PREFIX}/lib/devkit/include/lzo-2.10" -DLZO2_LIBRARY="${PREFIX}/lib/devkit/lib/liblzo2.so" \
  -DLZ4_INCLUDE_DIR="${PREFIX}/lib/devkit/include/lz4-1.10.0" -DLZ4_LIBRARY="${PREFIX}/lib/devkit/lib/liblz4.so" \
  -DZSTD_INCLUDE_DIR="${PREFIX}/lib/devkit/include/zstd-1.5.7" -DZSTD_LIBRARY="${PREFIX}/lib/devkit/lib/libzstd.so" \
  -DOPENSSL_INCLUDE_DIR="${PREFIX}/lib/devkit/include/openssl-3.5.9" \
  -DOPENSSL_CRYPTO_LIBRARY="${PREFIX}/lib/devkit/lib/libcrypto.so" -DOPENSSL_SSL_LIBRARY="${PREFIX}/lib/devkit/lib/libssl.so" \
  -DLIBXML2_INCLUDE_DIR="${PREFIX}/lib/devkit/include/libxml2-2.15.4" -DLIBXML2_LIBRARY="${PREFIX}/lib/devkit/lib/libxml2.so"
# CMake requires iconv for the libxml2 backend, unlike the forge Autotools
# configuration. Use the existing channel libiconv to preserve XML support.
# Expat and Nettle remain disabled as in forge; retain the GPL/LZO backends.
for feature in HAVE_LIBLZO2 HAVE_LIBLZ4 HAVE_LIBLZMA HAVE_LIBZSTD HAVE_LIBZ HAVE_LIBBZ2 HAVE_LIBXML2; do
  grep -q "^#define ${feature} 1" build/config.h
done
cmake --build build --parallel "${CPU_COUNT}"
if [[ "${DEVKIT_RUN_TESTS:-1}" == 1 ]]; then
  ctest --test-dir build --output-on-failure --parallel "${CPU_COUNT}"
fi
cmake --install build

# Keep development layout handling in this recipe until channel coverage is complete.
python3 "${RECIPE_DIR}/relocate-development.py"
