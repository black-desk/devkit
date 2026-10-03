#!/usr/bin/env bash
set -euxo pipefail

for tool in gcc ar ld make rustup; do
  test -x "${BUILD_PREFIX}/bin/${tool}"
done
test -f "${BUILD_PREFIX}/share/rust-toolchain/version"

RUST_TOOLCHAIN="$(cat "${BUILD_PREFIX}/share/rust-toolchain/version")"
test "${RUST_TOOLCHAIN}" = 1.98.1
SYSROOT="${BUILD_PREFIX}/x86_64-pc-linux-gnu/sysroot"
test -d "${SYSROOT}"

export RUSTUP_HOME="${SRC_DIR}/.rustup"
export CARGO_HOME="${SRC_DIR}/.cargo"
export CARGO_TARGET_DIR="${SRC_DIR}/target"
export GIT_CEILING_DIRECTORIES="$(dirname "${SRC_DIR}")"
export CC="${BUILD_PREFIX}/bin/gcc"
export AR="${BUILD_PREFIX}/bin/ar"
export CFLAGS="--sysroot=${SYSROOT} -O2 -pipe"
export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="${CC}"
export RUSTFLAGS="-C link-arg=--sysroot=${SYSROOT} -C link-arg=-Wl,-rpath-link,${SYSROOT}/lib64"
# Keep release optimization while reducing the memory needed by upstream's fat LTO.
export CARGO_PROFILE_RELEASE_LTO=thin
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-2}"

mkdir -p \
  "${RUSTUP_HOME}" \
  "${CARGO_HOME}" \
  "${CARGO_TARGET_DIR}" \
  "${PREFIX}/bin" \
  "${PREFIX}/share/bash-completion/completions" \
  "${PREFIX}/share/fish/vendor_completions.d" \
  "${PREFIX}/share/zsh/site-functions"

export YAZI_NO_GITCL=1
export YAZI_GEN_COMPLETIONS=1
export VERGEN_BUILD_DATE=2026-09-01

"${BUILD_PREFIX}/bin/rustup" toolchain install "${RUST_TOOLCHAIN}" \
  --profile minimal \
  --no-self-update

"${BUILD_PREFIX}/bin/rustup" run "${RUST_TOOLCHAIN}" cargo build \
  --locked --release --package yazi-fm --package yazi-cli

for binary in yazi ya; do
  install -m 0755 "${CARGO_TARGET_DIR}/release/${binary}" "${PREFIX}/bin/${binary}"
  completion_dir=yazi-boot/completions
  [[ "$binary" == ya ]] && completion_dir=yazi-cli/completions
  install -m 0644 "${completion_dir}/${binary}.bash" "${PREFIX}/share/bash-completion/completions/${binary}"
  install -m 0644 "${completion_dir}/${binary}.fish" "${PREFIX}/share/fish/vendor_completions.d/${binary}.fish"
  install -m 0644 "${completion_dir}/_${binary}" "${PREFIX}/share/zsh/site-functions/_${binary}"
done
