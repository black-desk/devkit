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
export LDFLAGS="${DEVKIT_FLAGS} --ld-path=${BUILD_PREFIX}/bin/ld.lld -L${PREFIX}/lib/devkit/lib -L${PREFIX}/lib -Wl,-rpath-link,${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib"
test -d "${SYSROOT}"
test -x "${CC}"

export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="${CC}"
export RUSTFLAGS="-C link-arg=--no-default-config -C link-arg=--config=${BUILD_PREFIX}/share/devkit/clang.cfg -C link-arg=-L${PREFIX}/lib/devkit/lib -L${PREFIX}/lib -C link-arg=-Wl,-rpath-link,${PREFIX}/lib -C link-arg=-Wl,--enable-new-dtags,-rpath,\$ORIGIN/../lib"
devkit_rustup() {
  env -u LD_LIBRARY_PATH LD_PRELOAD="${BUILD_PREFIX}/lib/libgcc_s.so.1" \
    "${BUILD_PREFIX}/bin/rustup" "$@"
}

# Require the channel PCRE2 probe before Cargo so its binding cannot silently
# fall back to building a second, bundled copy.
export PKG_CONFIG="${BUILD_PREFIX}/bin/pkg-config"
export PKG_CONFIG_LIBDIR="${PREFIX}/lib/devkit/lib/pkgconfig"
export PKG_CONFIG_PATH="${PREFIX}/lib/devkit/lib/pkgconfig"
export PCRE2_SYS_STATIC=0
"${PKG_CONFIG}" --exists libpcre2-8
"${PKG_CONFIG}" --libs libpcre2-8 | grep -F "${PREFIX}/lib/devkit/lib/pkgconfig/../../lib/libpcre2-8.so"

test -x "${BUILD_PREFIX}/bin/rustup"
test -f "${BUILD_PREFIX}/share/rust-toolchain/version"

RUST_TOOLCHAIN="$(cat "${BUILD_PREFIX}/share/rust-toolchain/version")"
test "${RUST_TOOLCHAIN}" = 1.98.1

export RUSTUP_HOME="${SRC_DIR}/.rustup"
export CARGO_HOME="${SRC_DIR}/.cargo"
export CARGO_TARGET_DIR="${SRC_DIR}/target"
# Rattler-Build's temporary source directory is below this repository. Stop
# ripgrep's build script from discovering the devkit repository and embedding
# its commit hash in the upstream binary's version output.
export GIT_CEILING_DIRECTORIES="$(dirname "${SRC_DIR}")"

mkdir -p \
  "${RUSTUP_HOME}" \
  "${CARGO_HOME}" \
  "${CARGO_TARGET_DIR}" \
  "${PREFIX}/bin" \
  "${PREFIX}/share/bash-completion/completions" \
  "${PREFIX}/share/fish/vendor_completions.d" \
  "${PREFIX}/share/man/man1" \
  "${PREFIX}/share/zsh/site-functions"

devkit_rustup toolchain install "${RUST_TOOLCHAIN}" \
  --profile minimal \
  --no-self-update

# Cargo must not depend on rustup shims installed on the build host.
export RUSTC="$(devkit_rustup which --toolchain "${RUST_TOOLCHAIN}" rustc)"
export RUSTDOC="$(devkit_rustup which --toolchain "${RUST_TOOLCHAIN}" rustdoc)"

devkit_rustup run "${RUST_TOOLCHAIN}" cargo build \
  --locked \
  --profile release-lto \
  --features pcre2

binary="${CARGO_TARGET_DIR}/release-lto/rg"
test -x "${binary}"
install -m 0755 "${binary}" "${PREFIX}/bin/rg"

"${PREFIX}/bin/rg" --generate man >"${PREFIX}/share/man/man1/rg.1"
"${PREFIX}/bin/rg" --generate complete-bash >"${PREFIX}/share/bash-completion/completions/rg"
"${PREFIX}/bin/rg" --generate complete-fish >"${PREFIX}/share/fish/vendor_completions.d/rg.fish"
"${PREFIX}/bin/rg" --generate complete-zsh >"${PREFIX}/share/zsh/site-functions/_rg"
