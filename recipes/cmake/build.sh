#!/usr/bin/env bash
set -euxo pipefail
source "${SRC_DIR}/devkit-build/build-env.sh"
# ncurses form.h includes <ncurses/curses.h>, while CMake also includes
# <form.h>; retain both the isolated root and its ncurses subdirectory.
export CFLAGS="${CFLAGS} -isystem ${PREFIX}/include/ncurses-6.6"
export CXXFLAGS="${CXXFLAGS} -isystem ${PREFIX}/include/ncurses-6.6"
export LDFLAGS="${LDFLAGS} -pthread -L${PREFIX}/lib/llvm-runtime -lgcc_s"
export PKG_CONFIG="${BUILD_PREFIX}/bin/pkgconf"
export PKG_CONFIG_LIBDIR="${PREFIX}/lib/pkgconfig"
unset PKG_CONFIG_PATH
# Use the previous-stage CMake, like the forge recipe. "System" libraries here
# mean explicit channel host inputs, confined to PREFIX and the glibc sysroot.
cmake -S . -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_C_COMPILER="${CC}" -DCMAKE_CXX_COMPILER="${CXX}" \
  -DCMAKE_C_FLAGS="${CFLAGS}" -DCMAKE_CXX_FLAGS="${CXXFLAGS}" \
  -DCMAKE_AR="${AR}" -DCMAKE_RANLIB="${RANLIB}" \
  -DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}" \
  '-DCMAKE_INSTALL_RPATH=$ORIGIN/../lib' \
  -DCMAKE_USE_SYSTEM_LIBRARIES=ON -DCMAKE_USE_SYSTEM_LIBARCHIVE=ON \
  -DCMAKE_USE_SYSTEM_JSONCPP=ON -DCMAKE_USE_SYSTEM_CPPDAP=ON \
  -DCMake_ENABLE_DEBUGGER=ON -DBUILD_CursesDialog=ON -DBUILD_QtDialog=OFF \
  -DBUILD_TESTING=ON \
  -DCMAKE_FIND_ROOT_PATH="${SYSROOT};${PREFIX}" \
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
  -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
  -DCURL_INCLUDE_DIR="${PREFIX}/include/curl-8.22.0" -DCURL_LIBRARY_RELEASE="${PREFIX}/lib/libcurl.so" \
  -DEXPAT_INCLUDE_DIR="${PREFIX}/include/expat-2.8.5" -DEXPAT_LIBRARY="${PREFIX}/lib/libexpat.so" \
  -DLibArchive_INCLUDE_DIR="${PREFIX}/include/libarchive-3.8.9" -DLibArchive_LIBRARY="${PREFIX}/lib/libarchive.so" \
  -DJsonCpp_INCLUDE_DIR="${PREFIX}/include/jsoncpp-1.9.8" -DJsonCpp_LIBRARY="${PREFIX}/lib/libjsoncpp.so" \
  -Djsoncpp_DIR="${PREFIX}/lib/cmake/jsoncpp" -Dcppdap_DIR="${PREFIX}/lib/cmake/cppdap" \
  -DLibUV_INCLUDE_DIR="${PREFIX}/include/libuv-1.52.1" -DLibUV_LIBRARY="${PREFIX}/lib/libuv.so" \
  -DLibRHash_INCLUDE_DIR="${PREFIX}/include/rhash-1.4.6" -DLibRHash_LIBRARY="${PREFIX}/lib/librhash.so" \
  -DZLIB_INCLUDE_DIR="${PREFIX}/include/zlib-1.3.2" -DZLIB_LIBRARY="${PREFIX}/lib/libz.so" \
  -DCURSES_INCLUDE_PATH="${PREFIX}/include/ncurses-6.6/ncurses" \
  -DCURSES_NCURSES_LIBRARY="${PREFIX}/lib/libncurses.so" \
  -DCURSES_EXTRA_LIBRARY="${PREFIX}/lib/libtinfo.so" \
  -DCURSES_FORM_LIBRARY="${PREFIX}/lib/libform.so" \
  -DCURSES_FORM_INCLUDE_DIR="${PREFIX}/include/ncurses-6.6/ncurses"
# Fail rather than silently losing external backends or the curses frontend.
for feature in CMAKE_USE_SYSTEM_LIBARCHIVE CMAKE_USE_SYSTEM_JSONCPP CMAKE_USE_SYSTEM_CPPDAP BUILD_CursesDialog CMake_ENABLE_DEBUGGER; do
  grep -q "^${feature}:[^=]*=ON$" build/CMakeCache.txt
done
cmake --build build --parallel "${CPU_COUNT}"
# Match the forge smoke subset; broader tests exercise absent developer tools.
ctest --test-dir build --output-on-failure --parallel "${CPU_COUNT}" -R 'CTestTestParallel|DOWNLOAD'
cmake --install build
"${STRIP}" --strip-unneeded "${PREFIX}/bin/"{cmake,ctest,cpack,ccmake}
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"
