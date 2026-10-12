#!/usr/bin/env bash
set -euxo pipefail
source "${SRC_DIR}/devkit-build/build-env.sh"
export LDFLAGS="${LDFLAGS} -L${PREFIX}/lib/llvm-runtime -lgcc_s"
cmake -S build/cmake -B devkit-build-tree -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_INSTALL_LIBDIR=lib \
  -DCMAKE_C_COMPILER="${CC}" -DCMAKE_CXX_COMPILER="${CXX}" \
  -DCMAKE_AR="${AR}" -DCMAKE_RANLIB="${RANLIB}" \
  -DCMAKE_C_FLAGS="${CFLAGS}" -DCMAKE_CXX_FLAGS="${CXXFLAGS}" \
  -DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}" \
  -DCMAKE_SHARED_LINKER_FLAGS="${LDFLAGS}" \
  -DCMAKE_FIND_ROOT_PATH="${SYSROOT};${PREFIX}" \
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
  -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
  -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY \
  -DZSTD_BUILD_STATIC=ON -DZSTD_BUILD_SHARED=ON \
  -DZSTD_PROGRAMS_LINK_SHARED=ON -DZSTD_ZLIB_SUPPORT=ON \
  -DZLIB_INCLUDE_DIR="${PREFIX}/include/zlib-1.3.2" \
  -DZLIB_LIBRARY="${PREFIX}/lib/libz.so" \
  -DZSTD_BUILD_TESTS=ON
cmake --build devkit-build-tree --parallel "${CPU_COUNT}"
devkit_test ctest --test-dir devkit-build-tree --output-on-failure --parallel "${CPU_COUNT}"
cmake --install devkit-build-tree
make -C contrib/pzstd -j"${CPU_COUNT}" all
install -m 0755 contrib/pzstd/pzstd "${PREFIX}/bin/pzstd"
mkdir -p "${PREFIX}/include/zstd-${LIBRARY_VERSION}"
mv "${PREFIX}/include/zstd.h" "${PREFIX}/include/zstd_errors.h" \
  "${PREFIX}/include/zstd-${LIBRARY_VERSION}/"
sed -i "s|includedir=.*|includedir=\${prefix}/include/zstd-${LIBRARY_VERSION}|; s|Libs:.*|Libs: \${libdir}/libzstd.so|" \
  "${PREFIX}/lib/pkgconfig/libzstd.pc"
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"
