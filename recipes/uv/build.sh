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
export LDFLAGS="${DEVKIT_FLAGS} --ld-path=${BUILD_PREFIX}/bin/ld.lld -L${PREFIX}/lib -Wl,-rpath-link,${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib"
test -d "${SYSROOT}"
test -x "${CC}"

export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="${CC}"
export RUSTFLAGS="-C link-arg=--no-default-config -C link-arg=--config=${BUILD_PREFIX}/share/devkit/clang.cfg -C link-arg=-L${PREFIX}/lib -C link-arg=-Wl,-rpath-link,${PREFIX}/lib -C link-arg=-Wl,-rpath,${PREFIX}/lib"
devkit_rustup() {
  env -u LD_LIBRARY_PATH LD_PRELOAD="${BUILD_PREFIX}/lib/libgcc_s.so.1" \
    "${BUILD_PREFIX}/bin/rustup" "$@"
}

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

# Cargo must not depend on rustup shims installed on the build host.
export RUSTC="$(devkit_rustup which --toolchain "${RUST_TOOLCHAIN}" rustc)"
export RUSTDOC="$(devkit_rustup which --toolchain "${RUST_TOOLCHAIN}" rustdoc)"

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
