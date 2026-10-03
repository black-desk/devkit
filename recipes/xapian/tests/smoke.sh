#!/usr/bin/env bash
set -euxo pipefail
unset LD_LIBRARY_PATH
export PKG_CONFIG_LIBDIR="${PREFIX}/lib/pkgconfig:${PREFIX}/share/pkgconfig"
export PKG_CONFIG_PATH="${PKG_CONFIG_LIBDIR}"
test "$(command -v pkg-config)" = "${PREFIX}/bin/pkg-config"
cflags="$(pkg-config --cflags xapian-core)"
libs="$(pkg-config --libs xapian-core)"
[[ " $cflags " != *" -I${PREFIX}/include "* ]]
[[ " $libs " != *" -L${PREFIX}/lib "* ]]
g++ $cflags tests/consumer.cpp $libs -Wl,-rpath,"${PREFIX}/lib" -o consumer
./consumer
ldd ./consumer >linked.txt
grep -F "${PREFIX}/lib/libxapian.so" linked.txt
grep -F "${PREFIX}/lib/libstdc++.so" linked.txt
grep -F "${PREFIX}/lib/libz.so" linked.txt
config="${PREFIX}/libexec/xapian/bin/xapian-config"
test ! -e "${PREFIX}/bin/xapian-config"
test "$("$config" --version)" = 'xapian-config - xapian-core 1.4.32'
[[ "$("$config" --cxxflags)" == *"${PREFIX}/include/xapian-1.4.32"* ]]
test "$("$config" --libs)" = "${PREFIX}/lib/libxapian.so"
test "$("$config" --ltlibs)" = "${PREFIX}/lib/libxapian.so"
g++ $("$config" --cxxflags) tests/consumer.cpp $("$config" --libs) -Wl,-rpath,"${PREFIX}/lib" -o consumer-config
./consumer-config
