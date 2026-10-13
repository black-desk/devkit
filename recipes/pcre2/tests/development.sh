#!/usr/bin/env bash
set -euxo pipefail
unset LD_LIBRARY_PATH LD_PRELOAD
export PKG_CONFIG_LIBDIR="${PREFIX}/lib/devkit/lib/pkgconfig"
unset PKG_CONFIG_PATH
flags="--no-default-config --config=${PREFIX}/share/devkit/clang.cfg"
for linkage in shared static; do
  static=OFF
  [[ "$linkage" != static ]] || static=ON
  cmake -S tests -B "build-${linkage}" -G Ninja \
    -DCMAKE_C_COMPILER="${PREFIX}/bin/clang" \
    -DCMAKE_C_FLAGS="${flags}" \
    -DCMAKE_EXE_LINKER_FLAGS="${flags}" \
    -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
    -DCMAKE_INSTALL_RPATH="${PREFIX}/lib" \
    -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=OFF \
    -DPCRE2_DIR="${PREFIX}/lib/devkit/lib/cmake/pcre2" \
    -DPCRE2_USE_STATIC_LIBS="${static}"
  cmake --build "build-${linkage}" --parallel 4
  for width in 8 16 32; do
    "./build-${linkage}/probe-${width}"
    if [[ "$linkage" == shared ]]; then
      ldd "build-${linkage}/probe-${width}" | grep -F "libpcre2-${width}.so.0 =>" | grep -F "${PREFIX}/"
    fi
  done
  "./build-${linkage}/probe-posix"
done
for width in 8 16 32; do
  test "$(pkg-config --libs "libpcre2-${width}")" = "$(dirname "$(pkg-config --path "libpcre2-${width}")")/../../lib/libpcre2-${width}.so"
done
