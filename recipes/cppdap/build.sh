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
export LDFLAGS="${LDFLAGS} -pthread -lgcc_s"
# Build a test-only GTest prefix from source with the same compiler/runtime.
cmake -S test-googletest -B gtest-build -G Ninja \
  -DCMAKE_PREFIX_PATH="${PREFIX}/lib/devkit" \
  -DCMAKE_INSTALL_PREFIX="${SRC_DIR}/gtest-install" \
  -DCMAKE_CXX_COMPILER="${CXX}" -DCMAKE_CXX_FLAGS="${CXXFLAGS}" \
  -DCMAKE_AR="${AR}" -DCMAKE_RANLIB="${RANLIB}" \
  -DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}" -DBUILD_SHARED_LIBS=OFF
cmake --build gtest-build --target install --parallel "${CPU_COUNT}"
cmake -S . -B build -G Ninja \
  -DCMAKE_PREFIX_PATH="${PREFIX}/lib/devkit" \
  -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=OFF \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_INSTALL_DATAROOTDIR=lib/devkit/share \
  -DCMAKE_INSTALL_LIBEXECDIR=lib/devkit/libexec \
  -DCMAKE_BUILD_RPATH="${PREFIX}/lib/devkit/lib" \
  -DCMAKE_INSTALL_LIBDIR=lib/devkit/lib -DCMAKE_INSTALL_INCLUDEDIR="lib/devkit/include/cppdap-${LIBRARY_VERSION}" \
  -DCMAKE_C_COMPILER="${CC}" -DCMAKE_CXX_COMPILER="${CXX}" \
  -DCMAKE_C_FLAGS="${CFLAGS}" -DCMAKE_CXX_FLAGS="${CXXFLAGS}" \
  -DCMAKE_AR="${AR}" -DCMAKE_RANLIB="${RANLIB}" \
  -DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}" -DCMAKE_SHARED_LINKER_FLAGS="${LDFLAGS}" \
  '-DCMAKE_INSTALL_RPATH=$ORIGIN:$ORIGIN/../lib/devkit/lib' \
  -DBUILD_SHARED_LIBS=ON -DCPPDAP_USE_EXTERNAL_JSONCPP_PACKAGE=ON \
  -Djsoncpp_DIR="${PREFIX}/lib/devkit/lib/cmake/jsoncpp" \
  -DCPPDAP_BUILD_TESTS=ON -DCPPDAP_USE_EXTERNAL_GTEST_PACKAGE=ON \
  -DGTest_DIR="${SRC_DIR}/gtest-install/lib/cmake/GTest"
cmake --build build --parallel "${CPU_COUNT}"
if [[ "${DEVKIT_RUN_TESTS:-1}" == 1 ]]; then
  ctest --test-dir build --output-on-failure
fi
cmake --install build
cmake -S . -B static-build -G Ninja \
  -DCMAKE_PREFIX_PATH="${PREFIX}/lib/devkit" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_INSTALL_DATAROOTDIR=lib/devkit/share \
  -DCMAKE_INSTALL_LIBEXECDIR=lib/devkit/libexec \
  -DCMAKE_INSTALL_LIBDIR=lib/devkit/lib -DCMAKE_INSTALL_INCLUDEDIR="lib/devkit/include/cppdap-${LIBRARY_VERSION}" \
  -DCMAKE_C_COMPILER="${CC}" -DCMAKE_CXX_COMPILER="${CXX}" \
  -DCMAKE_C_FLAGS="${CFLAGS}" -DCMAKE_CXX_FLAGS="${CXXFLAGS}" \
  -DCMAKE_AR="${AR}" -DCMAKE_RANLIB="${RANLIB}" \
  -DBUILD_SHARED_LIBS=OFF -DCPPDAP_USE_EXTERNAL_JSONCPP_PACKAGE=ON \
  -Djsoncpp_DIR="${PREFIX}/lib/devkit/lib/cmake/jsoncpp"
cmake --build static-build --parallel "${CPU_COUNT}"
# Preserve the installed shared target; expose static explicitly as an archive.
install -m644 static-build/libcppdap.a "${PREFIX}/lib/devkit/lib/libcppdap.a"

# Seed tools retain public-library RPATH. Only dirty supplies runtime SONAME
# aliases for them; result/selfhost install exclusively in the private libdir.
if [[ "${SYSROOT_TRIPLET:-}" == x86_64-conda-linux-gnu ]]; then
  for library in "${PREFIX}/lib/devkit/lib/"libcppdap.so.*; do
    [[ -f "${library}" ]] || continue
    soname="$(readelf -d "${library}" | sed -n 's/.*(SONAME).*\[\(.*\)\].*/\1/p')"
    [[ -n "${soname}" && "${soname}" != */* ]] || continue
    ln -sfn "devkit/lib/${soname}" "${PREFIX}/lib/${soname}"
  done
fi
