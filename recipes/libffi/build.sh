#!/usr/bin/env bash
set -euxo pipefail

export PATH="${BUILD_PREFIX}/bin:${PATH}"
export CC="${BUILD_PREFIX}/bin/clang"
export CXX="${BUILD_PREFIX}/bin/clang++"
export AR="${BUILD_PREFIX}/bin/llvm-ar"
export RANLIB="${BUILD_PREFIX}/bin/llvm-ranlib"
export NM="${BUILD_PREFIX}/bin/llvm-nm"
export STRIP="${BUILD_PREFIX}/bin/llvm-strip"
export CFLAGS="--no-default-config --config=${BUILD_PREFIX}/lib/devkit/share/devkit/clang.cfg -O2 -fPIC"
export CXXFLAGS="${CFLAGS}"
export CPPFLAGS=""
export LDFLAGS="--no-default-config --config=${BUILD_PREFIX}/lib/devkit/share/devkit/clang.cfg -L${PREFIX}/lib/devkit/lib -Wl,-rpath-link,${PREFIX}/lib/devkit/lib -Wl,--enable-new-dtags,-rpath,${PREFIX}/lib/devkit/lib"
export PKG_CONFIG="${BUILD_PREFIX}/bin/pkg-config"
export PKG_CONFIG_LIBDIR="${PREFIX}/lib/devkit/lib/pkgconfig"
export PKG_CONFIG_PATH="${PKG_CONFIG_LIBDIR}"

./configure --prefix="${PREFIX}" --libdir="${PREFIX}/lib/devkit/lib" \
  --includedir="${PREFIX}/lib/devkit/include/libffi-3.4.8" --datarootdir="${PREFIX}/lib/devkit/share" --disable-static --disable-docs
make -j"${CPU_COUNT}"
make install

# Post-link exception: upstream Libtool/Waf embeds its configured installation
# directory and offers no per-target relative install RUNPATH interface.
# TODO: upstream separate build/install RUNPATH support.
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"
