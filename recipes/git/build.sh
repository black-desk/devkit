#!/usr/bin/env bash
set -euxo pipefail

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

export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="${CC}"
export RUSTFLAGS="-C link-arg=--no-default-config -C link-arg=--config=${BUILD_PREFIX}/share/devkit/clang.cfg -C link-arg=-L${PREFIX}/lib/devkit/lib -L${PREFIX}/lib -C link-arg=-Wl,-rpath-link,${PREFIX}/lib -C link-arg=-Wl,-rpath,${PREFIX}/lib"
devkit_rustup() {
  env -u LD_LIBRARY_PATH LD_PRELOAD="${BUILD_PREFIX}/lib/libgcc_s.so.1" \
    "${BUILD_PREFIX}/bin/rustup" "$@"
}

: "${GIT_VERSION:?rattler-build must provide GIT_VERSION}"
: "${OPENSSL_VERSION:?rattler-build must provide OPENSSL_VERSION}"
: "${CURL_VERSION:?rattler-build must provide CURL_VERSION}"
: "${ZLIB_VERSION:?rattler-build must provide ZLIB_VERSION}"
: "${PCRE2_VERSION:?rattler-build must provide PCRE2_VERSION}"
: "${EXPAT_VERSION:?rattler-build must provide EXPAT_VERSION}"
: "${SYSROOT_TRIPLET:?rattler-build must provide SYSROOT_TRIPLET}"

test -x "${BUILD_PREFIX}/bin/make"
test -x "${BUILD_PREFIX}/bin/perl"
test -x "${BUILD_PREFIX}/bin/pkg-config"
test -x "${BUILD_PREFIX}/bin/rustup"
test -f "${BUILD_PREFIX}/share/rust-toolchain/version"

test -d "${SYSROOT}"

CURL_CONFIG="${PREFIX}/libexec/curl/bin/curl-config"
test -x "${CURL_CONFIG}"

RUST_TOOLCHAIN="$(cat "${BUILD_PREFIX}/share/rust-toolchain/version")"
test "${RUST_TOOLCHAIN}" = 1.98.1

for include in \
  "curl-${CURL_VERSION}" \
  "openssl-${OPENSSL_VERSION}" \
  "zlib-${ZLIB_VERSION}" \
  "pcre2-${PCRE2_VERSION}" \
  "expat-${EXPAT_VERSION}"; do
  test -d "${PREFIX}/lib/devkit/include/${include}"
done

for library in \
  libcurl.so \
  libssl.so \
  libcrypto.so \
  libz.so \
  libpcre2-8.so \
  libexpat.so; do
  test -f "${BUILD_PREFIX}/lib/devkit/lib/${library}"
done

export PATH="${BUILD_PREFIX}/bin:${PATH}"
export PKG_CONFIG="${BUILD_PREFIX}/bin/pkg-config"
export PKG_CONFIG_PATH="${PREFIX}/lib/devkit/lib/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"

COMMON_CFLAGS="${CFLAGS}"
EXTERNAL_CFLAGS="$(
  "${PKG_CONFIG}" --cflags libcurl openssl zlib libpcre2-8 expat
)"
CFLAGS="${COMMON_CFLAGS} ${EXTERNAL_CFLAGS}"

CURL_CFLAGS="$("${PKG_CONFIG}" --cflags libcurl)"
CURL_LDFLAGS="$("${PKG_CONFIG}" --libs-only-l --libs-only-other libcurl)"
if [[ -z "${CURL_LDFLAGS}" ]]; then
  CURL_LDFLAGS="$("${PKG_CONFIG}" --libs libcurl)"
fi

# Git's Makefile accepts exact library paths for these interfaces. Supplying
# them explicitly prevents feature detection from falling back to host headers
# or unqualified -l flags.
EXPAT_LIBEXPAT="${PREFIX}/lib/devkit/lib/libexpat.so"
OPENSSL_LIBSSL="${PREFIX}/lib/devkit/lib/libssl.so"
LIB_4_CRYPTO="${PREFIX}/lib/devkit/lib/libcrypto.so"

export RUSTUP_HOME="${SRC_DIR}/.rustup"
export CARGO_HOME="${SRC_DIR}/.cargo"
mkdir -p "${RUSTUP_HOME}" "${CARGO_HOME}"

devkit_rustup toolchain install "${RUST_TOOLCHAIN}" \
  --profile minimal \
  --no-self-update

# Cargo must not depend on rustup shims installed on the build host.
export RUSTC="$(devkit_rustup which --toolchain "${RUST_TOOLCHAIN}" rustc)"
export RUSTDOC="$(devkit_rustup which --toolchain "${RUST_TOOLCHAIN}" rustdoc)"

# EXTLIBS is overridden as a command-line variable because Git otherwise adds
# unqualified -lpcre2-8 and -lz. This list preserves its Linux defaults while
# selecting exact channel libraries.
EXTERNAL_LIBS="${PREFIX}/lib/devkit/lib/libpcre2-8.so \
${PREFIX}/lib/devkit/lib/libz.so \
${PREFIX}/lib/devkit/lib/libcrypto.so \
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
STRIP = ${STRIP}
CFLAGS = ${CFLAGS}
LDFLAGS = ${LDFLAGS} -Wl,--enable-new-dtags,-rpath,'\$\$ORIGIN/../lib:\$\$ORIGIN/../../lib'
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
  devkit_rustup run "${RUST_TOOLCHAIN}" make "$@"
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
