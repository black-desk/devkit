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

# Upstream reserves the self-update feature for its own installer. Keep the
# performance allocator, but omit development/test and self-update features.
devkit_rustup run "${RUST_TOOLCHAIN}" cargo build \
  --locked \
  --release \
  --package uv \
  --bin uv \
  --bin uvx \
  --no-default-features \
  --features performance

for binary in uv uvx; do
  install -m 0755 "${CARGO_TARGET_DIR}/release/${binary}" "${PREFIX}/bin/${binary}"
  "${PREFIX}/bin/${binary}" --generate-shell-completion bash >"${PREFIX}/share/bash-completion/completions/${binary}"
  "${PREFIX}/bin/${binary}" --generate-shell-completion fish >"${PREFIX}/share/fish/vendor_completions.d/${binary}.fish"
  "${PREFIX}/bin/${binary}" --generate-shell-completion zsh >"${PREFIX}/share/zsh/site-functions/_${binary}"
done

python3 "${BUILD_PREFIX}/share/devkit/finalize-elf.py" "${PREFIX}"
