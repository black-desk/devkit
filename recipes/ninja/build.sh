#!/usr/bin/env bash
set -euxo pipefail
source "${SRC_DIR}/devkit-build/build-env.sh"
export LDFLAGS="${LDFLAGS} -pthread -L${PREFIX}/lib/llvm-runtime -lgcc_s"
cmake -S . -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_C_COMPILER="${CC}" -DCMAKE_CXX_COMPILER="${CXX}" \
  -DCMAKE_C_FLAGS="${CFLAGS}" -DCMAKE_CXX_FLAGS="${CXXFLAGS}" \
  -DCMAKE_AR="${AR}" -DCMAKE_RANLIB="${RANLIB}" \
  -DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}" \
  '-DCMAKE_INSTALL_RPATH=$ORIGIN/../lib' \
  -DCMAKE_FIND_ROOT_PATH="${SYSROOT};${PREFIX}" \
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
  -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY \
  -DRE2C=RE2C-NOTFOUND -DBUILD_TESTING=ON \
  -DFETCHCONTENT_SOURCE_DIR_GOOGLETEST="${SRC_DIR}/test-googletest" \
  -DFETCHCONTENT_FULLY_DISCONNECTED=ON -DINSTALL_GTEST=OFF -DBUILD_GMOCK=OFF
cmake --build build --parallel "${CPU_COUNT}"
devkit_test ctest --test-dir build --output-on-failure
cmake --install build
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"
