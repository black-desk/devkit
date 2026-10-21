#!/usr/bin/env bash
set -euxo pipefail

export PKG_CONFIG_LIBDIR="${PREFIX}/lib/devkit/lib/pkgconfig"
export PKG_CONFIG_PATH="${PKG_CONFIG_LIBDIR}"
# Intentional splitting of pkg-config compiler and linker flags.
# shellcheck disable=SC2046
"${PREFIX}/bin/clang" --no-default-config \
  --config="${PREFIX}/lib/devkit/share/devkit/clang.cfg" \
  $(pkg-config --cflags talloc) tests/probe.c $(pkg-config --libs talloc) \
  "-Wl,--enable-new-dtags,-rpath,${PREFIX}/lib/devkit/lib" -o probe
./probe
