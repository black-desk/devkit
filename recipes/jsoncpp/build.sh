#!/usr/bin/env bash
set -euxo pipefail
source "${SRC_DIR}/devkit-build/build-env.sh"
export LDFLAGS="${LDFLAGS} -pthread -L${PREFIX}/lib/llvm-runtime -lgcc_s"
cmake -S . -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_INSTALL_INCLUDEDIR="include/jsoncpp-${LIBRARY_VERSION}" \
  -DCMAKE_C_COMPILER="${CC}" -DCMAKE_CXX_COMPILER="${CXX}" \
  -DCMAKE_C_FLAGS="${CFLAGS}" -DCMAKE_CXX_FLAGS="${CXXFLAGS}" \
  -DCMAKE_AR="${AR}" -DCMAKE_RANLIB="${RANLIB}" \
  -DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}" -DCMAKE_SHARED_LINKER_FLAGS="${LDFLAGS}" \
  '-DCMAKE_INSTALL_RPATH=$ORIGIN:$ORIGIN/../lib' \
  -DBUILD_SHARED_LIBS=ON -DBUILD_STATIC_LIBS=ON \
  -DJSONCPP_WITH_TESTS=ON -DJSONCPP_WITH_POST_BUILD_UNITTEST=ON
cmake --build build --parallel "${CPU_COUNT}"
devkit_test ctest --test-dir build --output-on-failure
cmake --install build
python3 - <<'PYMETA'
import os
from pathlib import Path
p = Path(os.environ['PREFIX']) / 'lib/pkgconfig/jsoncpp.pc'
s = p.read_text()
s = '\n'.join('prefix=${pcfiledir}/../..' if x.startswith('prefix=') else
              'exec_prefix=${prefix}' if x.startswith('exec_prefix=') else x
              for x in s.splitlines()) + '\n'
s = s.replace('-L${libdir} -ljsoncpp', '${libdir}/libjsoncpp.so')
p.write_text(s)
PYMETA
"${CXX}" ${CXXFLAGS} ${LDFLAGS} -I"${PREFIX}/include/jsoncpp-${LIBRARY_VERSION}" \
  "${RECIPE_DIR}/tests/probe.cpp" "${PREFIX}/lib/libjsoncpp.so" \
  '-Wl,--enable-new-dtags,-rpath,$ORIGIN/runtime-lib' -o library-probe
ln -s "${PREFIX}/lib" runtime-lib
./library-probe
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"
