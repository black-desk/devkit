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
unset PKG_CONFIG_PATH
export CPPFLAGS="${CPPFLAGS} -I${PREFIX}/include/krb5-1.22.2"
export LDFLAGS="${LDFLAGS} -Wl,-rpath,${SRC_DIR}/lib/.libs"
# Match the exact seed's native features. HTTP/3, IDN2, Brotli and LDAP
# are absent from its closure; do not discover host backends.
./configure --prefix="${PREFIX}" --libdir="${PREFIX}/lib" \
  --includedir="${PREFIX}/include/curl-${CURL_VERSION}" \
  --enable-shared --enable-static --enable-websockets --enable-manual \
  --with-openssl --with-zlib --with-zstd --with-libpsl \
  --with-libssh2 --with-nghttp2 --with-gssapi="${PREFIX}" \
  --with-gssapi-includes="${PREFIX}/include/krb5-1.22.2" \
  --with-ca-bundle="${PREFIX}/etc/ssl/certs/ca-certificates.crt" \
  --without-ca-path --without-ca-fallback \
  --without-ngtcp2 --without-quiche --without-libidn2 --without-libssh \
  --without-brotli --disable-ares --disable-ldap --disable-ldaps
# Libtool drops bare absolute library paths while composing libcurl.so.
# Pass exact dependency paths through the linker, preserving every backend.
private_libraries=(ssl crypto z nghttp2 ssh2 gssapi_krb5 krb5 k5crypto com_err psl zstd)
private_link=""
private_pc=""
for library in "${private_libraries[@]}"; do
  test -f "${PREFIX}/lib/lib${library}.so"
  private_link+=" -Wl,${PREFIX}/lib/lib${library}.so"
  private_pc+=" \${libdir}/lib${library}.so"
done
private_link+=" -ldl -pthread"
private_pc+=" -ldl -pthread"
make -j"${CPU_COUNT}" LIBCURL_PC_LIBS_PRIVATE="${private_link}"
make install LIBCURL_PC_LIBS_PRIVATE="${private_link}"
install -d -m 0755 "${PREFIX}/libexec/curl/bin"
mv "${PREFIX}/bin/curl-config" "${PREFIX}/libexec/curl/bin/curl-config"
rm -rf "${PREFIX}/lib/cmake/CURL"
rm -f "${PREFIX}/lib/libcurl.la" "${PREFIX}/bin/wcurl"
export CURL_PRIVATE_PC="${private_pc}"
python3 - <<'PY'
import os
from pathlib import Path
p = Path(os.environ['PREFIX']) / 'lib/pkgconfig/libcurl.pc'
lines = p.read_text().splitlines()
lines = ['prefix=${pcfiledir}/../..' if x.startswith('prefix=') else
         'exec_prefix=${prefix}' if x.startswith('exec_prefix=') else
         'libdir=${prefix}/lib' if x.startswith('libdir=') else
         'includedir=${prefix}/include/curl-' + os.environ['CURL_VERSION']
         if x.startswith('includedir=') else
         'Libs: ${libdir}/libcurl.so' if x.startswith('Libs:') else
         'Requires.private:' if x.startswith('Requires.private:') else
         'Libs.private:' + os.environ['CURL_PRIVATE_PC'] if x.startswith('Libs.private:') else x
         for x in lines]
# Curl's public headers do not expose backend types. Express private linkage
# with exact DSO paths instead of importing all backend include/link flags.
p.write_text('\n'.join(lines) + '\n')
PY
for linkage in shared static; do
  if [[ "${linkage}" == shared ]]; then curl_library=libcurl.so; else curl_library=libcurl.a; fi
  "${CC}" ${CFLAGS} ${LDFLAGS} -I"${PREFIX}/include/curl-${CURL_VERSION}" \
    "${RECIPE_DIR}/tests/probe.c" "${PREFIX}/lib/${curl_library}" ${private_link} \
    '-Wl,--enable-new-dtags,-rpath,$ORIGIN/runtime-lib' -o "${linkage}-probe"
done
mv shared-probe library-probe
ln -s "${PREFIX}/lib" runtime-lib
./library-probe
./static-probe
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"
