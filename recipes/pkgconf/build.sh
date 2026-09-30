#!/usr/bin/env bash
set -euxo pipefail

: "${PKGCONF_VERSION:?rattler-build must provide PKGCONF_VERSION}"
: "${SYSROOT_TRIPLET:?rattler-build must provide SYSROOT_TRIPLET}"

test -x "${BUILD_PREFIX}/bin/gcc"
test -x "${BUILD_PREFIX}/bin/as"
test -x "${BUILD_PREFIX}/bin/ld"

SYSROOT="${BUILD_PREFIX}/${SYSROOT_TRIPLET}/sysroot"
test -d "${SYSROOT}"

export PATH="${BUILD_PREFIX}/bin:${PATH}"
export CC="${BUILD_PREFIX}/bin/gcc"
export CFLAGS="--sysroot=${SYSROOT} -O2 -pipe"
export LDFLAGS="--sysroot=${SYSROOT}"

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
