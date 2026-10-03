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

cp "${BUILD_PREFIX}/share/gnuconfig/config.guess" config.guess
cp "${BUILD_PREFIX}/share/gnuconfig/config.sub" config.sub
export CPPFLAGS="$(pkg-config --cflags zlib)"
export LIBS="$(pkg-config --libs zlib)"
# Xapian clears LIBS before AC_SEARCH_LIBS. Verify the selected library, then
# supply its exact path as the search result instead of adding a broad -L path.
printf '#include <zlib.h>\nint main(void) { return zlibVersion() == 0; }\n' >check-zlib.c
"${CC}" ${CFLAGS} ${CPPFLAGS} check-zlib.c ${LIBS} ${LDFLAGS} -o check-zlib
./check-zlib
export ac_cv_search_zlibVersion="${LIBS}"
./configure --prefix="${PREFIX}" --libdir="${PREFIX}/lib" \
	--includedir="${PREFIX}/include/xapian-${PKG_VERSION}" \
	--enable-shared --disable-static --disable-documentation --disable-maintainer-mode
make -j"${CPU_COUNT}"
make install
rm -f "${PREFIX}/lib/libxapian.la"

# Keep upstream's option parser, but relocate its prefix and use exact libraries.
mkdir -p "${PREFIX}/libexec/xapian/bin"
mv "${PREFIX}/bin/xapian-config" "${PREFIX}/libexec/xapian/bin/"
# Installed substitutions no longer contain the template's library suffix.
sed -i -e 's|^prefix=.*|prefix=$(CDPATH="" cd -- "$(dirname -- "$0")/../../.." \&\& pwd)|' \
	-e 's|echo "$L-lxapian$D"|echo "${exec_prefix}/lib/libxapian.so"|' \
	-e 's|echo "$L-lxapian"|echo "${exec_prefix}/lib/libxapian.so"|' \
	"${PREFIX}/libexec/xapian/bin/xapian-config"
cat >"${PREFIX}/lib/pkgconfig/xapian-core.pc" <<EOF
prefix=\${pcfiledir}/../..
libdir=\${prefix}/lib
includedir=\${prefix}/include/xapian-${PKG_VERSION}

Name: Xapian
Description: Full-text search engine
Version: ${PKG_VERSION}
Libs: \${libdir}/libxapian.so
Cflags: -I\${includedir}
Requires.private: zlib
EOF
