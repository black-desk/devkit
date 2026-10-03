#!/usr/bin/env bash
set -euxo pipefail

SYSROOT="${BUILD_PREFIX}/x86_64-pc-linux-gnu/sysroot"
test -d "${SYSROOT}"
export PATH="${BUILD_PREFIX}/bin:${PATH}"
export CC="${BUILD_PREFIX}/bin/gcc"
export CXX="${BUILD_PREFIX}/bin/g++"
export CFLAGS="--sysroot=${SYSROOT} -O2 -pipe -fPIC"
export CXXFLAGS="${CFLAGS}"
export LDFLAGS="--sysroot=${SYSROOT} -Wl,-rpath,${PREFIX}/lib"
export PKG_CONFIG="${BUILD_PREFIX}/bin/pkg-config"
export PKG_CONFIG_LIBDIR="${PREFIX}/lib/pkgconfig:${PREFIX}/share/pkgconfig"
export PKG_CONFIG_PATH="${PKG_CONFIG_LIBDIR}"
export LD_LIBRARY_PATH="${PREFIX}/lib:${BUILD_PREFIX}/lib"

# Installed Python utility shebangs must refer to the host/runtime interpreter.
export PATH="${PREFIX}/bin:${BUILD_PREFIX}/bin:${PATH}"
meson setup build --prefix="${PREFIX}" --libdir=lib \
	--includedir="include/glib-${PKG_VERSION}" --buildtype=release \
	--default-library=shared --wrap-mode=nodownload \
	-Dtests=false -Dinstalled_tests=false -Dintrospection=disabled \
	-Ddocumentation=false -Dman-pages=disabled -Dnls=disabled \
	-Dselinux=disabled -Dlibmount=disabled -Dlibelf=disabled \
	-Ddtrace=disabled -Dsystemtap=disabled -Dsysprof=disabled
meson compile -C build -j "${CPU_COUNT}"
meson install -C build

# Preserve upstream Requires fields while making library paths exact and
# metadata relocatable. System libraries such as -pthread remain unchanged.
python - <<'PY'
import os
import re
from pathlib import Path
prefix = Path(os.environ['PREFIX'])
for path in (prefix / 'lib/pkgconfig').glob('*.pc'):
    if path.name not in {'glib-2.0.pc', 'gobject-2.0.pc', 'gmodule-2.0.pc',
                         'gmodule-export-2.0.pc', 'gmodule-no-export-2.0.pc',
                         'gthread-2.0.pc', 'gio-2.0.pc', 'gio-unix-2.0.pc',
                         'girepository-2.0.pc'}:
        continue
    text = path.read_text().replace(str(prefix), '${prefix}')
    text = re.sub(r'^prefix=.*$', 'prefix=${pcfiledir}/../..', text, flags=re.M)
    text = text.replace('-L${libdir} ', '')
    text = re.sub(r'-l(glib-2\.0|gobject-2\.0|gmodule-2\.0|gthread-2\.0|gio-2\.0|girepository-2\.0)\b',
                  r'${libdir}/lib\1.so', text)
    path.write_text(text)
PY
