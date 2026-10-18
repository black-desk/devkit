#!/usr/bin/env bash
set -euxo pipefail

# Bootstrap skips suites in dirty/result; standalone builds run them by default.
case "${DEVKIT_RUN_TESTS:-1}" in
  0 | 1) ;;
  *)
    printf 'error: DEVKIT_RUN_TESTS must be 0 or 1\n' >&2
    exit 1
    ;;
esac
: "${BUILD_PREFIX:?}"
: "${PREFIX:?}"
export SYSROOT="${BUILD_PREFIX}/${SYSROOT_TRIPLET:-x86_64-pc-linux-gnu}/sysroot"
export CC="${BUILD_PREFIX}/bin/clang"
export CXX="${BUILD_PREFIX}/bin/clang++"
if [[ "${SYSROOT_TRIPLET:-}" == x86_64-conda-linux-gnu ]]; then
  # Prepare the fresh seed build environment with unversioned driver names.
  ln -sfn clang-23 "${BUILD_PREFIX}/bin/clang"
  ln -sfn clang++-23 "${BUILD_PREFIX}/bin/clang++"
  DEVKIT_FLAGS="--start-no-unused-arguments --no-default-config --sysroot=${SYSROOT} --gcc-install-dir=${BUILD_PREFIX}/lib/gcc/x86_64-conda-linux-gnu/16.2.0 --rtlib=compiler-rt --unwindlib=none --end-no-unused-arguments"
else
  DEVKIT_FLAGS="--no-default-config --config=${BUILD_PREFIX}/lib/devkit/share/devkit/clang.cfg"
fi
export AR="${BUILD_PREFIX}/bin/llvm-ar"
export RANLIB="${BUILD_PREFIX}/bin/llvm-ranlib"
export NM="${BUILD_PREFIX}/bin/llvm-nm"
export STRIP="${BUILD_PREFIX}/bin/llvm-strip"
export OBJCOPY="${BUILD_PREFIX}/bin/llvm-objcopy"
export OBJDUMP="${BUILD_PREFIX}/bin/llvm-objdump"
export READELF="${BUILD_PREFIX}/bin/llvm-readelf"
export LD="${BUILD_PREFIX}/bin/ld.lld"
export PATH="${BUILD_PREFIX}/bin:${PATH}"
export CFLAGS="${DEVKIT_FLAGS} -O2 -fPIC"
if [[ "${SYSROOT_TRIPLET:-}" == x86_64-conda-linux-gnu ]]; then
  export CXXFLAGS="${CFLAGS} --start-no-unused-arguments -stdlib=libc++ -nostdinc++ -isystem ${PREFIX}/lib/devkit/include/libcxx-23.1.3/c++/v1 --end-no-unused-arguments"
else
  # clang.cfg already selects libc++ headers. Adding a second copy from the
  # native host prefix breaks C wrapper include_next. Both prefixes select
  # the same libc++ package from the completed input generation.
  export CXXFLAGS="${CFLAGS}"
fi
export CPPFLAGS="${DEVKIT_FLAGS}"
export LDFLAGS="${DEVKIT_FLAGS} --ld-path=${BUILD_PREFIX}/bin/ld.lld -L${PREFIX}/lib/devkit/lib -Wl,-rpath-link,${PREFIX}/lib/devkit/lib"
test -d "${SYSROOT}"
test -x "${CC}"
# ncurses form.h includes <ncurses/curses.h>, while CMake also includes
# <form.h>; retain both the isolated root and its ncurses subdirectory.
export CFLAGS="${CFLAGS} -isystem ${PREFIX}/lib/devkit/include/ncurses-6.6"
export CXXFLAGS="${CXXFLAGS} -isystem ${PREFIX}/lib/devkit/include/ncurses-6.6"
export LDFLAGS="${LDFLAGS} -pthread -lgcc_s"
export PKG_CONFIG="${BUILD_PREFIX}/bin/pkgconf"
export PKG_CONFIG_LIBDIR="${PREFIX}/lib/devkit/lib/pkgconfig"
unset PKG_CONFIG_PATH
# CMake itself defaults BUILD_WITH_INSTALL_RPATH to ON. Keep the build-tree
# tools on private input libraries; native installation writes relative paths.
# Use the previous-stage CMake, like the forge recipe. "System" libraries here
# mean explicit channel host inputs, confined to PREFIX and the glibc sysroot.
cmake -S . -B build -G Ninja \
  -DCMAKE_PREFIX_PATH="${PREFIX}/lib/devkit" \
  -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=OFF \
  -DCMAKE_BUILD_WITH_INSTALL_RPATH=OFF \
  -DCMAKE_DATA_DIR=share/cmake-3.31 \
  -DCMAKE_DOC_DIR=lib/devkit/share/doc/cmake-3.31 \
  -DCMAKE_MAN_DIR=lib/devkit/share/man \
  -DCMAKE_INFO_DIR=lib/devkit/share/info \
  -DCMAKE_XDGDATA_DIR=lib/devkit/share \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_BUILD_RPATH="${PREFIX}/lib/devkit/lib" \
  -DCMAKE_C_COMPILER="${CC}" -DCMAKE_CXX_COMPILER="${CXX}" \
  -DCMAKE_C_FLAGS="${CFLAGS}" -DCMAKE_CXX_FLAGS="${CXXFLAGS}" \
  -DCMAKE_AR="${AR}" -DCMAKE_RANLIB="${RANLIB}" \
  -DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}" \
  '-DCMAKE_INSTALL_RPATH=$ORIGIN/../lib/devkit/lib' \
  -DCMAKE_USE_SYSTEM_LIBRARIES=ON -DCMAKE_USE_SYSTEM_LIBARCHIVE=ON \
  -DCMAKE_USE_SYSTEM_JSONCPP=ON -DCMAKE_USE_SYSTEM_CPPDAP=ON \
  -DCMake_ENABLE_DEBUGGER=ON -DBUILD_CursesDialog=ON -DBUILD_QtDialog=OFF \
  -DBUILD_TESTING=ON \
  -DCMAKE_FIND_ROOT_PATH="${SYSROOT};${PREFIX}" \
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
  -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
  -DCURL_INCLUDE_DIR="${PREFIX}/lib/devkit/include/curl-8.22.0" -DCURL_LIBRARY_RELEASE="${PREFIX}/lib/devkit/lib/libcurl.so" \
  -DEXPAT_INCLUDE_DIR="${PREFIX}/lib/devkit/include/expat-2.8.5" -DEXPAT_LIBRARY="${PREFIX}/lib/devkit/lib/libexpat.so" \
  -DLibArchive_INCLUDE_DIR="${PREFIX}/lib/devkit/include/libarchive-3.8.9" -DLibArchive_LIBRARY="${PREFIX}/lib/devkit/lib/libarchive.so" \
  -DJsonCpp_INCLUDE_DIR="${PREFIX}/lib/devkit/include/jsoncpp-1.9.8" -DJsonCpp_LIBRARY="${PREFIX}/lib/devkit/lib/libjsoncpp.so" \
  -Djsoncpp_DIR="${PREFIX}/lib/devkit/lib/cmake/jsoncpp" -Dcppdap_DIR="${PREFIX}/lib/devkit/lib/cmake/cppdap" \
  -DLibUV_INCLUDE_DIR="${PREFIX}/lib/devkit/include/libuv-1.52.1" -DLibUV_LIBRARY="${PREFIX}/lib/devkit/lib/libuv.so" \
  -DLibRHash_INCLUDE_DIR="${PREFIX}/lib/devkit/include/rhash-1.4.6" -DLibRHash_LIBRARY="${PREFIX}/lib/devkit/lib/librhash.so" \
  -DZLIB_INCLUDE_DIR="${PREFIX}/lib/devkit/include/zlib-1.3.2" -DZLIB_LIBRARY="${PREFIX}/lib/devkit/lib/libz.so" \
  -DCURSES_INCLUDE_PATH="${PREFIX}/lib/devkit/include/ncurses-6.6/ncurses" \
  -DCURSES_NCURSES_LIBRARY="${PREFIX}/lib/devkit/lib/libncurses.so" \
  -DCURSES_EXTRA_LIBRARY="${PREFIX}/lib/devkit/lib/libtinfo.so" \
  -DCURSES_FORM_LIBRARY="${PREFIX}/lib/devkit/lib/libform.so" \
  -DCURSES_FORM_INCLUDE_DIR="${PREFIX}/lib/devkit/include/ncurses-6.6/ncurses"
# Fail rather than silently losing external backends or the curses frontend.
for feature in CMAKE_USE_SYSTEM_LIBARCHIVE CMAKE_USE_SYSTEM_JSONCPP CMAKE_USE_SYSTEM_CPPDAP BUILD_CursesDialog CMake_ENABLE_DEBUGGER; do
  grep -q "^${feature}:[^=]*=ON$" build/CMakeCache.txt
done
cmake --build build --parallel "${CPU_COUNT}"
# Match the forge smoke subset; broader tests exercise absent developer tools.
if [[ "${DEVKIT_RUN_TESTS:-1}" == 1 ]]; then
  ctest --test-dir build --output-on-failure --parallel "${CPU_COUNT}" -R 'CTestTestParallel|DOWNLOAD'
fi
cmake --install build
"${STRIP}" --strip-unneeded "${PREFIX}/bin/"{cmake,ctest,cpack,ccmake}
