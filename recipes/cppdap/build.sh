#!/usr/bin/env bash
set -euxo pipefail
source "${SRC_DIR}/devkit-build/build-env.sh"
export LDFLAGS="${LDFLAGS} -pthread -L${PREFIX}/lib/llvm-runtime -lgcc_s"
# Build a test-only GTest prefix from source with the same compiler/runtime.
cmake -S test-googletest -B gtest-build -G Ninja \
  -DCMAKE_INSTALL_PREFIX="${SRC_DIR}/gtest-install" \
  -DCMAKE_CXX_COMPILER="${CXX}" -DCMAKE_CXX_FLAGS="${CXXFLAGS}" \
  -DCMAKE_AR="${AR}" -DCMAKE_RANLIB="${RANLIB}" \
  -DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}" -DBUILD_SHARED_LIBS=OFF
cmake --build gtest-build --target install --parallel "${CPU_COUNT}"
cmake -S . -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_INSTALL_INCLUDEDIR="include/cppdap-${LIBRARY_VERSION}" \
  -DCMAKE_C_COMPILER="${CC}" -DCMAKE_CXX_COMPILER="${CXX}" \
  -DCMAKE_C_FLAGS="${CFLAGS}" -DCMAKE_CXX_FLAGS="${CXXFLAGS}" \
  -DCMAKE_AR="${AR}" -DCMAKE_RANLIB="${RANLIB}" \
  -DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}" -DCMAKE_SHARED_LINKER_FLAGS="${LDFLAGS}" \
  '-DCMAKE_INSTALL_RPATH=$ORIGIN:$ORIGIN/../lib' \
  -DBUILD_SHARED_LIBS=ON -DCPPDAP_USE_EXTERNAL_JSONCPP_PACKAGE=ON \
  -Djsoncpp_DIR="${PREFIX}/lib/cmake/jsoncpp" \
  -DCPPDAP_BUILD_TESTS=ON -DCPPDAP_USE_EXTERNAL_GTEST_PACKAGE=ON \
  -DGTest_DIR="${SRC_DIR}/gtest-install/lib/cmake/GTest"
cmake --build build --parallel "${CPU_COUNT}"
ctest --test-dir build --output-on-failure
cmake --install build
cmake -S . -B static-build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_INSTALL_INCLUDEDIR="include/cppdap-${LIBRARY_VERSION}" \
  -DCMAKE_C_COMPILER="${CC}" -DCMAKE_CXX_COMPILER="${CXX}" \
  -DCMAKE_C_FLAGS="${CFLAGS}" -DCMAKE_CXX_FLAGS="${CXXFLAGS}" \
  -DCMAKE_AR="${AR}" -DCMAKE_RANLIB="${RANLIB}" \
  -DBUILD_SHARED_LIBS=OFF -DCPPDAP_USE_EXTERNAL_JSONCPP_PACKAGE=ON \
  -Djsoncpp_DIR="${PREFIX}/lib/cmake/jsoncpp"
cmake --build static-build --parallel "${CPU_COUNT}"
# Preserve the installed shared target; expose static explicitly as an archive.
install -m644 static-build/libcppdap.a "${PREFIX}/lib/libcppdap.a"
"${CXX}" ${CXXFLAGS} ${LDFLAGS} -I"${PREFIX}/include/cppdap-${LIBRARY_VERSION}" \
  "${RECIPE_DIR}/tests/probe.cpp" "${PREFIX}/lib/libcppdap.so" \
  '-Wl,--enable-new-dtags,-rpath,$ORIGIN/runtime-lib' -o library-probe
ln -s "${PREFIX}/lib" runtime-lib
./library-probe
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"
