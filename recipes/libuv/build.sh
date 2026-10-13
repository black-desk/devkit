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
  DEVKIT_FLAGS="--no-default-config --config=${BUILD_PREFIX}/share/devkit/clang.cfg"
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
export LDFLAGS="${DEVKIT_FLAGS} --ld-path=${BUILD_PREFIX}/bin/ld.lld -L${PREFIX}/lib/devkit/lib -L${PREFIX}/lib -Wl,-rpath-link,${PREFIX}/lib"
test -d "${SYSROOT}"
test -x "${CC}"
cmake -S . -B build -G Ninja \
  -DCMAKE_PREFIX_PATH="${PREFIX}/lib/devkit" \
  -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=OFF \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_INSTALL_INCLUDEDIR="include/libuv-${LIBRARY_VERSION}" \
  -DCMAKE_C_COMPILER="${CC}" -DCMAKE_C_FLAGS="${CFLAGS}" \
  -DCMAKE_AR="${AR}" -DCMAKE_RANLIB="${RANLIB}" \
  -DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}" -DCMAKE_SHARED_LINKER_FLAGS="${LDFLAGS}" \
  '-DCMAKE_INSTALL_RPATH=$ORIGIN' -DCMAKE_BUILD_RPATH="${PWD}/build;${PREFIX}/lib" \
  -DLIBUV_BUILD_SHARED=ON -DLIBUV_BUILD_TESTS=ON -DBUILD_TESTING=ON
cmake --build build --target uv uv_a uv_run_tests --parallel "${CPU_COUNT}"
# Run the full shared-library suite; tests run against the build-tree RUNPATH.
if [[ "${DEVKIT_RUN_TESTS:-1}" == 1 ]]; then
  ctest --test-dir build -R '^uv_test$' --output-on-failure
fi
cmake --install build
python3 - <<'PY'
import os
from pathlib import Path
prefix = Path(os.environ['PREFIX'])
for path in (prefix / 'lib/pkgconfig').glob('libuv*.pc'):
    lines = path.read_text().splitlines()
    lines = ['prefix=${pcfiledir}/../..' if line.startswith('prefix=') else
             'libdir=${prefix}/lib' if line.startswith('libdir=') else
             'includedir=${prefix}/include/libuv-' + os.environ['LIBRARY_VERSION']
             if line.startswith('includedir=') else line for line in lines]
    text = '\n'.join(lines) + '\n'
    text = text.replace('-L${libdir} -l:libuv.a', '${libdir}/libuv.a')
    text = text.replace('-L${libdir} -luv', '${libdir}/libuv.so')
    path.write_text(text)
PY
"${CC}" ${CFLAGS} ${LDFLAGS} -I"${PREFIX}/include/libuv-${LIBRARY_VERSION}" \
  "${RECIPE_DIR}/tests/probe.c" "${PREFIX}/lib/libuv.so" \
  '-Wl,--enable-new-dtags,-rpath,$ORIGIN/runtime-lib' -o "${SRC_DIR}/uv-probe"

# Stage only this package's development interfaces; preserve runtime libraries.
python3 "${SRC_DIR}/devkit-build/stage-development.py" "${PREFIX}" --all
