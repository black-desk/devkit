#!/usr/bin/env bash
# Focused zlib layout probe; use an unpatched host CMake and pkgconf.
set -euo pipefail
prefix=$(realpath "${1:?usage: check-development-prefix.sh PREFIX}")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/src"
cat >"$work/src/CMakeLists.txt" <<'CMAKE'
cmake_minimum_required(VERSION 3.20)
project(layout C)
# Model upstream CMake adding its own installation prefix to system searches.
if(NOT "$ENV{PILOT_INSTALLED_CMAKE}" STREQUAL "1")
  list(PREPEND CMAKE_SYSTEM_PREFIX_PATH "$ENV{PILOT_PREFIX}")
else()
  get_filename_component(cmake_prefix "${CMAKE_ROOT}/../.." REALPATH)
  if(NOT cmake_prefix STREQUAL "$ENV{PILOT_PREFIX}")
    message(FATAL_ERROR "CMake is not installed in the pilot prefix")
  endif()
endif()
find_package(ZLIB REQUIRED)
get_filename_component(actual "${ZLIB_LIBRARY_RELEASE}" REALPATH)
get_filename_component(expected "$ENV{PILOT_PREFIX}/lib/libz.so.1" REALPATH)
if(EXPLICIT)
  if(NOT actual STREQUAL expected)
    message(FATAL_ERROR "Explicit lookup chose ${actual}, expected ${expected}")
  endif()
  if(NOT ZLIB_INCLUDE_DIR MATCHES "/lib/devkit/include/")
    message(FATAL_ERROR "Explicit lookup chose headers ${ZLIB_INCLUDE_DIR}")
  endif()
elseif(actual STREQUAL expected OR ZLIB_INCLUDE_DIR MATCHES "/lib/devkit/")
  message(FATAL_ERROR "Default lookup exposed channel development files")
endif()
add_executable(probe main.c)
target_link_libraries(probe PRIVATE ZLIB::ZLIB)
set_target_properties(probe PROPERTIES BUILD_RPATH "$ENV{PILOT_PREFIX}/lib")
CMAKE
cat >"$work/src/main.c" <<'C'
#include <zlib.h>
#include <stdio.h>
int main(void) { puts(zlibVersion()); return 0; }
C
export PILOT_PREFIX="$prefix"
unset CMAKE_PREFIX_PATH CMAKE_INCLUDE_PATH CMAKE_LIBRARY_PATH PKG_CONFIG_PATH PKG_CONFIG_LIBDIR
cmake -S "$work/src" -B "$work/default"
cmake -S "$work/src" -B "$work/explicit" -DEXPLICIT=ON \
  -DCMAKE_PREFIX_PATH="$prefix/lib/devkit" \
  -DCMAKE_INCLUDE_PATH="$prefix/lib/devkit/include/zlib-1.3.2"
cmake --build "$work/explicit"
env -u LD_LIBRARY_PATH -u LD_PRELOAD "$work/explicit/probe"
ldd "$work/explicit/probe" | tee "$work/ldd"
grep -F "$prefix/lib/libz.so.1" "$work/ldd"
case "$(pkg-config --variable=pcfiledir zlib)" in
  "$prefix"/*)
    printf 'default pkgconf exposed channel zlib\n' >&2
    exit 1
    ;;
esac
export PKG_CONFIG_LIBDIR="$prefix/lib/devkit/lib/pkgconfig"
pkg-config --cflags --libs zlib
clang $(pkg-config --cflags zlib) "$work/src/main.c" \
  $(pkg-config --libs zlib) -Wl,-rpath,"$prefix/lib" -o "$work/pc-probe"
env -u LD_LIBRARY_PATH -u LD_PRELOAD "$work/pc-probe"
clang $(pkg-config --cflags zlib) "$work/src/main.c" \
  "$prefix/lib/devkit/lib/libz.a" -o "$work/static-probe"
"$work/static-probe"
