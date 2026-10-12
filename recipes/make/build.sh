#!/usr/bin/env bash
set -euxo pipefail

# Refresh Autotools platform detection before configure.
cp "${BUILD_PREFIX}/share/gnuconfig/config.guess" ./build-aux/config.guess
cp "${BUILD_PREFIX}/share/gnuconfig/config.sub" ./build-aux/config.sub

source "${SRC_DIR}/devkit-build/build-env.sh"

./configure \
  --prefix="${PREFIX}" \
  --disable-dependency-tracking

# GNU Make's source tree can bootstrap itself without an existing make.
bash build.sh
devkit_test ./make check
./make install

# Preserve relocatable DT_RUNPATH; package tests run without loader overrides.
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"
