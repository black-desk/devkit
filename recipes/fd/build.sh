#!/usr/bin/env bash
set -euxo pipefail

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
  "${PREFIX}/share/bash-completion/completions" \
  "${PREFIX}/share/fish/vendor_completions.d" \
  "${PREFIX}/share/man/man1" \
  "${PREFIX}/share/zsh/site-functions"

"${BUILD_PREFIX}/bin/rustup" toolchain install "${RUST_TOOLCHAIN}" \
  --profile minimal \
  --no-self-update

"${BUILD_PREFIX}/bin/rustup" run "${RUST_TOOLCHAIN}" cargo build \
  --locked \
  --release

binary="${CARGO_TARGET_DIR}/release/fd"
test -x "${binary}"
install -m 0755 "${binary}" "${PREFIX}/bin/fd"

"${binary}" --gen-completions bash >"${PREFIX}/share/bash-completion/completions/fd"
"${binary}" --gen-completions fish >"${PREFIX}/share/fish/vendor_completions.d/fd.fish"
install -m 0644 contrib/completion/_fd "${PREFIX}/share/zsh/site-functions/_fd"
install -m 0644 doc/fd.1 "${PREFIX}/share/man/man1/fd.1"
