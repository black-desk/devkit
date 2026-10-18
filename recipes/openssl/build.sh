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

: "${OPENSSL_VERSION:?rattler-build must provide OPENSSL_VERSION}"
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

# OpenSSL's Configure and build machinery is Perl-based.
"${BUILD_PREFIX}/bin/perl" ./Configure \
  linux-x86_64 \
  --prefix="${PREFIX}" \
  --openssldir="${PREFIX}/etc/ssl" \
  --libdir=lib \
  enable-legacy \
  shared \
  no-docs \
  no-zlib

make -j"${CPU_COUNT}"
if [[ "${DEVKIT_RUN_TESTS:-1}" == 1 ]]; then
  make test
fi
make install
mkdir -p "${PREFIX}/lib/devkit/include/openssl-${OPENSSL_VERSION}"
mv "${PREFIX}/include/openssl" "${PREFIX}/lib/devkit/include/openssl-${OPENSSL_VERSION}/"

# These Perl helpers would make the OpenSSL runtime pull in Perl. The channel
# needs the C libraries and the OpenSSL CLI here; Perl remains a build input.
rm -f "${PREFIX}/bin/c_rehash"
rm -rf "${PREFIX}/etc/ssl/misc"

# OpenSSL looks for a single default PEM bundle beside its configuration file.
# The ca-certificates package owns the actual pinned bundle.
ln -s certs/ca-certificates.crt "${PREFIX}/etc/ssl/cert.pem"

cat >"${SRC_DIR}/devkit-consumer.c" <<'EOF'
#include <openssl/crypto.h>
#include <openssl/ssl.h>
#include <openssl/opensslv.h>

#include <stdio.h>

int main(void) {
  if (OPENSSL_VERSION_NUMBER != OpenSSL_version_num()) {
    return 1;
  }
  SSL_CTX *context = SSL_CTX_new(TLS_client_method());
  if (context == NULL) {
    return 1;
  }
  SSL_CTX_free(context);
  puts(OPENSSL_VERSION_TEXT);
  return 0;
}
EOF

"${CC}" \
  ${CFLAGS} ${LDFLAGS} \
  -I"${PREFIX}/lib/devkit/include/openssl-${OPENSSL_VERSION}" \
  "${SRC_DIR}/devkit-consumer.c" \
  "${PREFIX}/lib/libssl.so" \
  "${PREFIX}/lib/libcrypto.so" \
  -ldl \
  -pthread \
  -o "${SRC_DIR}/devkit-consumer"

env -u LD_LIBRARY_PATH -u LD_PRELOAD "${SRC_DIR}/devkit-consumer"

# Preserve relocatable DT_RUNPATH; package tests run without loader overrides.
# Post-link exception: OpenSSL uses common link flags for the CLI, libraries and provider modules at different installation depths.
# TODO: replace with target-specific upstream install/relink support.
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"

# Keep development layout handling in this recipe until channel coverage is complete.
python3 "${RECIPE_DIR}/relocate-development.py"
