#!/usr/bin/env bash
# No global loader override: only upstream Rust tool invocations are preloaded.
source "${BUILD_PREFIX}/share/devkit/build-env.sh"
export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="${CC}"
export RUSTFLAGS="-C link-arg=--no-default-config -C link-arg=--config=${BUILD_PREFIX}/share/devkit/clang.cfg -C link-arg=-L${PREFIX}/lib -C link-arg=-Wl,-rpath-link,${PREFIX}/lib -C link-arg=-Wl,-rpath,${PREFIX}/lib"
devkit_rustup() {
  env -u LD_LIBRARY_PATH LD_PRELOAD="${BUILD_PREFIX}/lib/libgcc_s.so.1" \
    "${BUILD_PREFIX}/bin/rustup" "$@"
}
