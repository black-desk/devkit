#!/usr/bin/env bash
set -euxo pipefail
unset LD_LIBRARY_PATH
export PKG_CONFIG_LIBDIR="${PREFIX}/lib/pkgconfig:${PREFIX}/share/pkgconfig"
export PKG_CONFIG_PATH="${PKG_CONFIG_LIBDIR}"
test "$(command -v pkg-config)" = "${PREFIX}/bin/pkg-config"
cflags="$(pkg-config --cflags gio-2.0 gobject-2.0)"
libs="$(pkg-config --libs gio-2.0 gobject-2.0)"
[[ " $cflags " != *" -I${PREFIX}/include "* ]]
[[ " $libs " != *" -L${PREFIX}/lib "* ]]
gcc $cflags tests/consumer.c $libs -Wl,-rpath,"${PREFIX}/lib" -o consumer
./consumer
ldd ./consumer >linked.txt
grep -F "${PREFIX}/lib/libglib-2.0.so" linked.txt
grep -F "${PREFIX}/lib/libffi.so" linked.txt
grep -F "${PREFIX}/lib/libpcre2-8.so" linked.txt
grep -F "${PREFIX}/lib/libz.so" linked.txt
gdbus-codegen --help
glib-mkenums --version
glib-compile-resources --version
