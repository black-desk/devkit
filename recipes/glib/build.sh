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

# Python helper shebangs must select the host/runtime interpreter.
export PATH="${PREFIX}/bin:${BUILD_PREFIX}/bin:${PATH}"
# Meson is an orchestration tool supplied by the pinned Pixi environment.
meson setup build --prefix="${PREFIX}" --libdir=lib/devkit/lib \
  --includedir="lib/devkit/include/glib-${PKG_VERSION}" \
  --datadir=lib/devkit/share --libexecdir=lib/devkit/libexec \
  --sysconfdir=lib/devkit/etc --localstatedir=lib/devkit/var \
  --buildtype=release --default-library=shared --wrap-mode=nodownload \
  -Dgdb_autoload_dir="${PREFIX}/lib/devkit/lib" \
  -Dtests=false -Dinstalled_tests=false -Dintrospection=disabled \
  -Ddocumentation=false -Dman-pages=disabled -Dnls=disabled \
  -Dselinux=disabled -Dlibmount=disabled -Ddtrace=disabled \
  -Dsystemtap=disabled -Dsysprof=disabled
meson compile -C build -j "${CPU_COUNT}"
meson install -C build

# Post-link exception: Meson installs several executables and module directories.
# Normalize newly installed ELF to relative channel RUNPATH.
# TODO: upstream separate build/install RUNPATH support.
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"
