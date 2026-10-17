#!/usr/bin/env bash
set -euxo pipefail
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
cp "${BUILD_PREFIX}/share/gnuconfig/"config.* .
export PKG_CONFIG="${BUILD_PREFIX}/bin/pkgconf"
export PKG_CONFIG_LIBDIR="${PREFIX}/lib/devkit/lib/pkgconfig"
unset PKG_CONFIG_PATH
export CPPFLAGS="${CPPFLAGS} -I${PREFIX}/lib/devkit/include/krb5-1.22.2"
export LDFLAGS="${LDFLAGS} -Wl,-rpath,${SRC_DIR}/lib/.libs"
# Match the exact seed's native features. HTTP/3, IDN2, Brotli and LDAP
# are absent from its closure; do not discover host backends.
./configure --prefix="${PREFIX}" --libdir="${PREFIX}/lib" \
  --includedir="${PREFIX}/lib/devkit/include/curl-${CURL_VERSION}" \
  --enable-shared --enable-static --enable-websockets --enable-manual \
  --with-openssl --with-zlib --with-zstd --with-libpsl \
  --with-libssh2 --with-nghttp2 --with-gssapi="${PREFIX}" \
  --with-gssapi-includes="${PREFIX}/lib/devkit/include/krb5-1.22.2" \
  --with-ca-bundle="${PREFIX}/etc/ssl/certs/ca-certificates.crt" \
  --without-ca-path --without-ca-fallback \
  --without-ngtcp2 --without-quiche --without-libidn2 --without-libssh \
  --without-brotli --disable-ares --disable-ldap --disable-ldaps
# Libtool drops bare absolute library paths while composing libcurl.so.
# Pass exact dependency paths through the linker, preserving every backend.
private_libraries=(ssl crypto z nghttp2 ssh2 gssapi_krb5 krb5 k5crypto com_err psl zstd)
private_link=""
for library in "${private_libraries[@]}"; do
  test -f "${PREFIX}/lib/devkit/lib/lib${library}.so"
  private_link+=" -Wl,${PREFIX}/lib/devkit/lib/lib${library}.so"
done
private_link+=" -ldl -pthread"
make -j"${CPU_COUNT}" LIBCURL_PC_LIBS_PRIVATE="${private_link}"
make install pkgconfigdir="${PREFIX}/lib/devkit/lib/pkgconfig" LIBCURL_PC_LIBS_PRIVATE="${private_link}"
rm -rf "${PREFIX}/lib/cmake/CURL"
rm -f "${PREFIX}/lib/libcurl.la" "${PREFIX}/bin/wcurl"
# Post-link exception: Libtool links both library and CLI with build/host paths; it lacks CMake-style separate build and install RUNPATH settings.
# TODO: replace with target-specific upstream install/relink support.
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"

# Stage only this package's development interfaces; preserve runtime libraries.
python3 "${SRC_DIR}/devkit-build/stage-development.py" "${PREFIX}" --all
