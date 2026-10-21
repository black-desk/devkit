#!/usr/bin/env bash
set -euxo pipefail

export SYSROOT="${BUILD_PREFIX}/${SYSROOT_TRIPLET:-x86_64-pc-linux-gnu}/sysroot"
export CC="${BUILD_PREFIX}/bin/clang"
export CXX="${BUILD_PREFIX}/bin/clang++"
DEVKIT_FLAGS="--no-default-config --config=${BUILD_PREFIX}/lib/devkit/share/devkit/clang.cfg"
export AR="${BUILD_PREFIX}/bin/llvm-ar"
export RANLIB="${BUILD_PREFIX}/bin/llvm-ranlib"
export NM="${BUILD_PREFIX}/bin/llvm-nm"
export PATH="${BUILD_PREFIX}/bin:${PATH}"
export CFLAGS="${DEVKIT_FLAGS} -O2 -fPIC"
export CXXFLAGS="${CFLAGS}"
export CPPFLAGS="${DEVKIT_FLAGS}"
export LDFLAGS="${DEVKIT_FLAGS} -L${PREFIX}/lib/devkit/lib -Wl,-rpath-link,${PREFIX}/lib/devkit/lib"
export PKG_CONFIG="${BUILD_PREFIX}/bin/pkg-config"
export PKG_CONFIG_LIBDIR="${PREFIX}/lib/devkit/lib/pkgconfig"
export PKG_CONFIG_PATH="${PKG_CONFIG_LIBDIR}"
export OPENSSL_NO_VENDOR=1
export OPENSSL_INCLUDE_DIR="${PREFIX}/lib/devkit/include/openssl-3.5.9"
export OPENSSL_LIB_DIR="${PREFIX}/lib/devkit/lib"
export OPENSSL_DYNAMIC=1
test -d "${SYSROOT}"
test -x "${CC}"

export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="${CC}"
export RUSTFLAGS="-C link-arg=--no-default-config -C link-arg=--config=${BUILD_PREFIX}/lib/devkit/share/devkit/clang.cfg -C link-arg=-L${PREFIX}/lib/devkit/lib -C link-arg=-Wl,-rpath-link,${PREFIX}/lib/devkit/lib -C link-arg=-Wl,--enable-new-dtags,-rpath,\$ORIGIN/../lib/devkit/lib"
devkit_rustup() {
	env -u LD_LIBRARY_PATH LD_PRELOAD="${BUILD_PREFIX}/lib/devkit/lib/libgcc_s.so.1" \
		"${BUILD_PREFIX}/bin/rustup" "$@"
}

RUST_TOOLCHAIN="$(cat "${BUILD_PREFIX}/lib/devkit/share/rust-toolchain/version")"
test "${RUST_TOOLCHAIN}" = 1.98.1
export RUSTUP_HOME="${SRC_DIR}/.rustup"
export CARGO_HOME="${SRC_DIR}/.cargo"
export CARGO_TARGET_DIR="${SRC_DIR}/target"
GIT_CEILING_DIRECTORIES="$(dirname "${SRC_DIR}")"
export GIT_CEILING_DIRECTORIES
export CARGO_PROFILE_RELEASE_LTO=thin
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-2}"
export GEN_ARTIFACTS="${SRC_DIR}/cli-artifacts"

mkdir -p "${RUSTUP_HOME}" "${CARGO_HOME}" "${CARGO_TARGET_DIR}" \
	"${PREFIX}/bin" "${PREFIX}/lib/devkit/share/man/man1" \
	"${PREFIX}/lib/devkit/share/bash-completion/completions" \
	"${PREFIX}/lib/devkit/share/fish/vendor_completions.d" \
	"${PREFIX}/lib/devkit/share/zsh/site-functions" \
	"${PREFIX}/etc/conda/env_vars.d"
devkit_rustup toolchain install "${RUST_TOOLCHAIN}" --profile minimal --no-self-update
RUSTC="$(devkit_rustup which --toolchain "${RUST_TOOLCHAIN}" rustc)"
RUSTDOC="$(devkit_rustup which --toolchain "${RUST_TOOLCHAIN}" rustdoc)"
export RUSTC RUSTDOC
devkit_rustup run "${RUST_TOOLCHAIN}" cargo build --locked --release --package typst-cli

install -m 0755 "${CARGO_TARGET_DIR}/release/typst" "${PREFIX}/bin/typst"
install -m 0644 "${GEN_ARTIFACTS}/"*.1 "${PREFIX}/lib/devkit/share/man/man1/"
"${PREFIX}/bin/typst" completions bash >"${PREFIX}/lib/devkit/share/bash-completion/completions/typst"
"${PREFIX}/bin/typst" completions fish >"${PREFIX}/lib/devkit/share/fish/vendor_completions.d/typst.fish"
"${PREFIX}/bin/typst" completions zsh >"${PREFIX}/lib/devkit/share/zsh/site-functions/_typst"
cat >"${PREFIX}/etc/conda/env_vars.d/typst.json" <<EOF
{"TYPST_PACKAGE_PATH": "${PREFIX}/lib/devkit/share/typst/packages", "TYPST_FONT_PATHS": "${PREFIX}/lib/devkit/share/fonts"}
EOF
