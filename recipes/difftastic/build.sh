#!/usr/bin/env bash
set -euxo pipefail

test -x "${BUILD_PREFIX}/bin/gcc"
test -x "${BUILD_PREFIX}/bin/rustup"
test -f "${BUILD_PREFIX}/share/rust-toolchain/version"

RUST_TOOLCHAIN="$(cat "${BUILD_PREFIX}/share/rust-toolchain/version")"
test "${RUST_TOOLCHAIN}" = 1.98.1

export RUSTUP_HOME="${SRC_DIR}/.rustup"
export CARGO_HOME="${SRC_DIR}/.cargo"
export CARGO_TARGET_DIR="${SRC_DIR}/target"

mkdir -p \
  "${RUSTUP_HOME}" \
  "${CARGO_HOME}" \
  "${CARGO_TARGET_DIR}" \
  "${PREFIX}/bin" \
  "${PREFIX}/share/man/man1"

"${BUILD_PREFIX}/bin/rustup" toolchain install "${RUST_TOOLCHAIN}" \
  --profile minimal \
  --no-self-update

"${BUILD_PREFIX}/bin/rustup" run "${RUST_TOOLCHAIN}" cargo build \
  --locked \
  --release

binary="${CARGO_TARGET_DIR}/release/difft"
test -x "${binary}"
install -m 0755 "${binary}" "${PREFIX}/bin/difft"
install -m 0644 difft.1 "${PREFIX}/share/man/man1/difft.1"
