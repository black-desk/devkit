#!/usr/bin/env bash
set -euxo pipefail

: "${GIT_VERSION:?rattler-build must provide GIT_VERSION}"
: "${OPENSSL_VERSION:?rattler-build must provide OPENSSL_VERSION}"
: "${CURL_VERSION:?rattler-build must provide CURL_VERSION}"
: "${ZLIB_VERSION:?rattler-build must provide ZLIB_VERSION}"
: "${PCRE2_VERSION:?rattler-build must provide PCRE2_VERSION}"
: "${EXPAT_VERSION:?rattler-build must provide EXPAT_VERSION}"
: "${SYSROOT_TRIPLET:?rattler-build must provide SYSROOT_TRIPLET}"

test -x "${BUILD_PREFIX}/bin/gcc"
test -x "${BUILD_PREFIX}/bin/ar"
test -x "${BUILD_PREFIX}/bin/ld"
test -x "${BUILD_PREFIX}/bin/make"
test -x "${BUILD_PREFIX}/bin/perl"
test -x "${BUILD_PREFIX}/bin/pkg-config"
test -x "${BUILD_PREFIX}/bin/rustup"
test -f "${BUILD_PREFIX}/share/rust-toolchain/version"

SYSROOT="${BUILD_PREFIX}/${SYSROOT_TRIPLET}/sysroot"
test -d "${SYSROOT}"

CURL_CONFIG="${BUILD_PREFIX}/libexec/curl/bin/curl-config"
test -x "${CURL_CONFIG}"

RUST_TOOLCHAIN="$(cat "${BUILD_PREFIX}/share/rust-toolchain/version")"
test "${RUST_TOOLCHAIN}" = 1.98.1

for include in \
  "curl-${CURL_VERSION}" \
  "openssl-${OPENSSL_VERSION}" \
  "zlib-${ZLIB_VERSION}" \
  "pcre2-${PCRE2_VERSION}" \
  "expat-${EXPAT_VERSION}"
do
  test -d "${BUILD_PREFIX}/include/${include}"
done

for library in \
  libcurl.so \
  libssl.so \
  libcrypto.so \
  libz.so \
  libpcre2-8.so \
  libexpat.so
do
  test -f "${BUILD_PREFIX}/lib/${library}"
done

export PATH="${BUILD_PREFIX}/bin:${PATH}"
export PKG_CONFIG="${BUILD_PREFIX}/bin/pkg-config"
export PKG_CONFIG_PATH="${BUILD_PREFIX}/lib/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"

CC="${BUILD_PREFIX}/bin/gcc"
AR="${BUILD_PREFIX}/bin/ar"
COMMON_CFLAGS="--sysroot=${SYSROOT} -O2 -pipe"
EXTERNAL_CFLAGS="$(
  "${PKG_CONFIG}" --cflags libcurl openssl zlib libpcre2-8 expat
)"
CFLAGS="${COMMON_CFLAGS} ${EXTERNAL_CFLAGS}"
LDFLAGS="--sysroot=${SYSROOT} -Wl,-rpath-link,${SYSROOT}/lib64"

CURL_CFLAGS="$("${PKG_CONFIG}" --cflags libcurl)"
CURL_LDFLAGS="$("${PKG_CONFIG}" --libs-only-l --libs-only-other libcurl)"
if [[ -z "${CURL_LDFLAGS}" ]]; then
  CURL_LDFLAGS="$("${PKG_CONFIG}" --libs libcurl)"
fi

# Git's Makefile accepts exact library paths for these interfaces. Supplying
# them explicitly prevents feature detection from falling back to host headers
# or unqualified -l flags.
EXPAT_LIBEXPAT="${BUILD_PREFIX}/lib/libexpat.so"
OPENSSL_LIBSSL="${BUILD_PREFIX}/lib/libssl.so"
LIB_4_CRYPTO="${BUILD_PREFIX}/lib/libcrypto.so"

export RUSTUP_HOME="${SRC_DIR}/.rustup"
export CARGO_HOME="${SRC_DIR}/.cargo"
mkdir -p "${RUSTUP_HOME}" "${CARGO_HOME}"

"${BUILD_PREFIX}/bin/rustup" toolchain install "${RUST_TOOLCHAIN}" \
  --profile minimal \
  --no-self-update

# EXTLIBS is overridden as a command-line variable because Git otherwise adds
# unqualified -lpcre2-8 and -lz. This list preserves its Linux defaults while
# selecting exact channel libraries.
EXTERNAL_LIBS="${BUILD_PREFIX}/lib/libpcre2-8.so \
${BUILD_PREFIX}/lib/libz.so \
${BUILD_PREFIX}/lib/libcrypto.so \
-pthread"

cat >config.mak <<EOF
prefix = ${PREFIX}
bindir = ${PREFIX}/bin
gitexecdir = libexec/git-core
template_dir = share/git-core/templates
sysconfdir = etc
RUNTIME_PREFIX = YesPlease
INSTALL_SYMLINKS = YesPlease
CC = ${CC}
AR = ${AR}
CFLAGS = ${CFLAGS}
LDFLAGS = ${LDFLAGS}
PERL_PATH = ${PREFIX}/bin/perl
SHELL_PATH = /bin/sh
CURL_CONFIG = ${CURL_CONFIG}
CURL_CFLAGS = ${CURL_CFLAGS}
CURL_LDFLAGS = ${CURL_LDFLAGS}
EXPAT_LIBEXPAT = ${EXPAT_LIBEXPAT}
OPENSSL_LIBSSL = ${OPENSSL_LIBSSL}
LIB_4_CRYPTO = ${LIB_4_CRYPTO}
USE_LIBPCRE2 = YesPlease
NO_TCLTK = YesPlease
NO_PYTHON = YesPlease
NO_GETTEXT = YesPlease
EOF

rustup_run_make() {
  "${BUILD_PREFIX}/bin/rustup" run "${RUST_TOOLCHAIN}" make "$@"
}

rustup_run_make -j"${CPU_COUNT}" \
  EXTLIBS="${EXTERNAL_LIBS}" \
  EXPAT_LIBEXPAT="${EXPAT_LIBEXPAT}" \
  OPENSSL_LIBSSL="${OPENSSL_LIBSSL}" \
  LIB_4_CRYPTO="${LIB_4_CRYPTO}"
rustup_run_make install INSTALL_STRIP=-s \
  EXTLIBS="${EXTERNAL_LIBS}" \
  EXPAT_LIBEXPAT="${EXPAT_LIBEXPAT}" \
  OPENSSL_LIBSSL="${OPENSSL_LIBSSL}" \
  LIB_4_CRYPTO="${LIB_4_CRYPTO}"
make -C contrib/subtree -j"${CPU_COUNT}" install \
  gitexecdir="${PREFIX}/libexec/git-core"
