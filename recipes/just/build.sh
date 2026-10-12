#!/usr/bin/env bash
set -euxo pipefail

source "${BUILD_PREFIX}/share/devkit/rust-env.sh"

test -x "${BUILD_PREFIX}/bin/rustup"
test -f "${BUILD_PREFIX}/share/rust-toolchain/version"

RUST_TOOLCHAIN="$(cat "${BUILD_PREFIX}/share/rust-toolchain/version")"
test "${RUST_TOOLCHAIN}" = 1.98.1

export RUSTUP_HOME="${SRC_DIR}/.rustup"
export CARGO_HOME="${SRC_DIR}/.cargo"
export CARGO_TARGET_DIR="${SRC_DIR}/target"
export GIT_CEILING_DIRECTORIES="$(dirname "${SRC_DIR}")"
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

devkit_rustup toolchain install "${RUST_TOOLCHAIN}" \
  --profile minimal \
  --no-self-update

devkit_rustup run "${RUST_TOOLCHAIN}" cargo build \
  --locked --release --bin just

install -m 0755 "${CARGO_TARGET_DIR}/release/just" "${PREFIX}/bin/just"
"${PREFIX}/bin/just" --completions bash >"${PREFIX}/share/bash-completion/completions/just"
"${PREFIX}/bin/just" --completions fish >"${PREFIX}/share/fish/vendor_completions.d/just.fish"
"${PREFIX}/bin/just" --completions zsh >"${PREFIX}/share/zsh/site-functions/_just"
mkdir -p "${PREFIX}/share/man/man1"
"${PREFIX}/bin/just" --man >"${PREFIX}/share/man/man1/just.1"

python3 "${BUILD_PREFIX}/share/devkit/finalize-elf.py" "${PREFIX}"
