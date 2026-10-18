#!/usr/bin/env bash
set -euxo pipefail

: "${BUILD_PREFIX:?}"
: "${PREFIX:?}"
export SYSROOT="${BUILD_PREFIX}/${SYSROOT_TRIPLET:-x86_64-pc-linux-gnu}/sysroot"
export CC="${BUILD_PREFIX}/bin/clang"
export CXX="${BUILD_PREFIX}/bin/clang++"
DEVKIT_FLAGS="--no-default-config --config=${BUILD_PREFIX}/lib/devkit/share/devkit/clang.cfg"
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
export LDFLAGS="${DEVKIT_FLAGS} --ld-path=${BUILD_PREFIX}/bin/ld.lld -L${PREFIX}/lib/devkit/lib -Wl,-rpath-link,${PREFIX}/lib/devkit/lib -Wl,-rpath,${PREFIX}/lib/devkit/lib"
test -d "${SYSROOT}"
test -x "${CC}"

export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="${CC}"
export RUSTFLAGS="-C link-arg=--no-default-config -C link-arg=--config=${BUILD_PREFIX}/lib/devkit/share/devkit/clang.cfg -C link-arg=-L${PREFIX}/lib/devkit/lib -C link-arg=-Wl,-rpath-link,${PREFIX}/lib/devkit/lib -C link-arg=-Wl,--enable-new-dtags,-rpath,\$ORIGIN/../lib/devkit/lib"
# Only upstream rustup/toolchain subprocesses receive this preload.
# Installed channel applications use their linked RUNPATH instead.
devkit_rustup() {
  env -u LD_LIBRARY_PATH LD_PRELOAD="${BUILD_PREFIX}/lib/devkit/lib/libgcc_s.so.1" \
    "${BUILD_PREFIX}/bin/rustup" "$@"
}

test -x "${BUILD_PREFIX}/bin/rustup"
test -f "${BUILD_PREFIX}/lib/devkit/share/rust-toolchain/version"

RUST_TOOLCHAIN="$(cat "${BUILD_PREFIX}/lib/devkit/share/rust-toolchain/version")"
test "${RUST_TOOLCHAIN}" = 1.98.1

export RUSTUP_HOME="${SRC_DIR}/.rustup"
export CARGO_HOME="${SRC_DIR}/.cargo"
export CARGO_TARGET_DIR="${SRC_DIR}/target"

mkdir -p \
  "${RUSTUP_HOME}" \
  "${CARGO_HOME}" \
  "${CARGO_TARGET_DIR}" \
  "${PREFIX}/bin" \
  "${PREFIX}/lib/devkit/share/man/man1"

devkit_rustup toolchain install "${RUST_TOOLCHAIN}" \
  --profile minimal \
  --no-self-update

# Cargo must not depend on rustup shims installed on the build host.
export RUSTC="$(devkit_rustup which --toolchain "${RUST_TOOLCHAIN}" rustc)"
export RUSTDOC="$(devkit_rustup which --toolchain "${RUST_TOOLCHAIN}" rustdoc)"

devkit_rustup run "${RUST_TOOLCHAIN}" cargo build \
  --locked \
  --release

binary="${CARGO_TARGET_DIR}/release/difft"
test -x "${binary}"
install -m 0755 "${binary}" "${PREFIX}/bin/difft"
install -m 0644 difft.1 "${PREFIX}/lib/devkit/share/man/man1/difft.1"
