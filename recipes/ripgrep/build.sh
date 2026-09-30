#!/usr/bin/env bash
set -euxo pipefail

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

"${BUILD_PREFIX}/bin/rustup" toolchain install "${RUST_TOOLCHAIN}" \
  --profile minimal \
  --no-self-update

"${BUILD_PREFIX}/bin/rustup" run "${RUST_TOOLCHAIN}" cargo build \
  --locked \
  --profile release-lto

binary="${CARGO_TARGET_DIR}/release-lto/rg"
test -x "${binary}"
install -m 0755 "${binary}" "${PREFIX}/bin/rg"

"${binary}" --generate man >"${PREFIX}/share/man/man1/rg.1"
"${binary}" --generate complete-bash >"${PREFIX}/share/bash-completion/completions/rg"
"${binary}" --generate complete-fish >"${PREFIX}/share/fish/vendor_completions.d/rg.fish"
"${binary}" --generate complete-zsh >"${PREFIX}/share/zsh/site-functions/_rg"
