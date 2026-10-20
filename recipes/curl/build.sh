#!/usr/bin/env bash
set -euxo pipefail
: "${BUILD_PREFIX:?}"
: "${PREFIX:?}"
# Record compiler paths in the prefix relocated by Conda at installation.
test "${BUILD_PREFIX}" = "${PREFIX}"
export SYSROOT="${BUILD_PREFIX}/${SYSROOT_TRIPLET:-x86_64-pc-linux-gnu}/sysroot"
export CC="${BUILD_PREFIX}/bin/clang"
export CXX="${BUILD_PREFIX}/bin/clang++"
if [[ "${SYSROOT_TRIPLET:-}" == x86_64-conda-linux-gnu ]]; then
  # Keep seed-owned compiler names; new aliases would become curl payload.
  export CC="${BUILD_PREFIX}/bin/clang-23"
  export CXX="${BUILD_PREFIX}/bin/clang++-23"
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
  # clang.cfg already selects libc++ headers; adding them again breaks the
  # C wrapper headers' include_next search.
  export CXXFLAGS="${CFLAGS}"
fi
export CPPFLAGS="${DEVKIT_FLAGS}"
export LDFLAGS="${DEVKIT_FLAGS} --ld-path=${BUILD_PREFIX}/bin/ld.lld -L${PREFIX}/lib/devkit/lib -Wl,-rpath-link,${PREFIX}/lib/devkit/lib -Wl,-rpath,${PREFIX}/lib/devkit/lib"
test -d "${SYSROOT}"
test -x "${CC}"
cp "${BUILD_PREFIX}/lib/devkit/share/gnuconfig/"config.* .
export PKG_CONFIG="${BUILD_PREFIX}/bin/pkgconf"
export PKG_CONFIG_LIBDIR="${PREFIX}/lib/devkit/lib/pkgconfig"
unset PKG_CONFIG_PATH
export CPPFLAGS="${CPPFLAGS} -I${PREFIX}/lib/devkit/include/krb5-1.22.2"
export LDFLAGS="${LDFLAGS} -Wl,-rpath,${SRC_DIR}/lib/.libs"
# Match the exact seed's native features. HTTP/3, IDN2, Brotli and LDAP
# are absent from its closure; do not discover host backends.
# curl overrides PKG_CONFIG_LIBDIR with <gssapi-root>/lib/pkgconfig during
# GSS-API detection. Point that root at the private library installation;
# the versioned header directory is supplied separately below.
./configure --prefix="${PREFIX}" \
  --datarootdir="${PREFIX}/lib/devkit/share" \
  --libexecdir="${PREFIX}/lib/devkit/libexec" \
  --sysconfdir="${PREFIX}/lib/devkit/etc" \
  --localstatedir="${PREFIX}/lib/devkit/var" \
  --sbindir="${PREFIX}/lib/devkit/sbin" --libdir="${PREFIX}/lib/devkit/lib" \
  --includedir="${PREFIX}/lib/devkit/include/curl-${CURL_VERSION}" \
  --enable-shared --enable-static --enable-websockets --enable-manual \
  --with-openssl --with-zlib --with-zstd --with-libpsl \
  --with-libssh2 --with-nghttp2 --with-gssapi="${PREFIX}/lib/devkit" \
  --with-gssapi-includes="${PREFIX}/lib/devkit/include/krb5-1.22.2" \
  --with-ca-bundle="${PREFIX}/lib/devkit/etc/ssl/certs/ca-certificates.crt" \
  --without-ca-path --without-ca-fallback \
  --without-ngtcp2 --without-quiche --without-libidn2 --without-libssh \
  --without-brotli --disable-ares --disable-ldap --disable-ldaps
make -j"${CPU_COUNT}"
make install configbindir="${PREFIX}/lib/devkit/libexec/curl/bin" pkgconfigdir="${PREFIX}/lib/devkit/lib/pkgconfig"
rm -rf "${PREFIX}/lib/cmake/CURL"
rm -f "${PREFIX}/lib/devkit/lib/libcurl.la" "${PREFIX}/bin/wcurl"
# Post-link exception: Libtool links both library and CLI with build/host paths; it lacks CMake-style separate build and install RUNPATH settings.
# TODO: replace with target-specific upstream install/relink support.
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"

# Seed tools retain public-library RPATH. Only dirty supplies runtime SONAME
# aliases for them; result/selfhost install exclusively in the private libdir.
if [[ "${SYSROOT_TRIPLET:-}" == x86_64-conda-linux-gnu ]]; then
  for library in "${PREFIX}/lib/devkit/lib/"libcurl.so.*; do
    [[ -f "${library}" ]] || continue
    soname="$(readelf -d "${library}" | sed -n 's/.*(SONAME).*\[\(.*\)\].*/\1/p')"
    [[ -n "${soname}" && "${soname}" != */* ]] || continue
    ln -sfn "devkit/lib/${soname}" "${PREFIX}/lib/${soname}"
  done
fi
