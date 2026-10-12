#!/usr/bin/env bash
set -euxo pipefail

: "${PKGCONF_VERSION:?rattler-build must provide PKGCONF_VERSION}"
: "${SYSROOT_TRIPLET:?rattler-build must provide SYSROOT_TRIPLET}"

source "${SRC_DIR}/devkit-build/build-env.sh"

meson setup build \
  --buildtype=release \
  --default-library=static \
  --prefix="${PREFIX}" \
  --libdir=lib \
  --wrap-mode=nofallback \
  -Dwith-system-libdir=/usr/lib:/usr/lib64 \
  -Dwith-system-includedir=/usr/include

meson compile -C build
meson test -C build --print-errorlogs

# This package intentionally exposes the command-line interface only. Keeping
# libpkgconf private avoids publishing another ordinary C library interface.
install -d -m 0755 "${PREFIX}/bin"
install -m 0755 build/pkgconf "${PREFIX}/bin/pkgconf"
ln -s pkgconf "${PREFIX}/bin/pkg-config"

# Preserve relocatable DT_RUNPATH; package tests run without loader overrides.
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"
