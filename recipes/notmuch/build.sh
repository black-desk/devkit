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

export XAPIAN_CONFIG="${PREFIX}/lib/devkit/libexec/xapian/bin/xapian-config"
./configure --prefix="${PREFIX}" --libdir="${PREFIX}/lib/devkit/lib" \
  --includedir="${PREFIX}/lib/devkit/include/notmuch-${PKG_VERSION}" \
  --sysconfdir="${PREFIX}/lib/devkit/etc" \
  --mandir="${PREFIX}/lib/devkit/share/man" \
  --infodir="${PREFIX}/lib/devkit/share/info" \
  --without-emacs --without-ruby --without-docs
# The CLI and shared C API are the package interface. lieer builds matching
# Python CFFI bindings in its own locked tool environment.
make -j"${CPU_COUNT}" notmuch-shared
make install-lib
install -Dm755 notmuch-shared "${PREFIX}/bin/notmuch"

# Post-link exception: upstream Libtool/Waf embeds its configured installation
# directory and offers no per-target relative install RUNPATH interface.
# TODO: upstream separate build/install RUNPATH support.
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"
