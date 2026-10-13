#!/usr/bin/env bash
set -euxo pipefail
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
export LDFLAGS="${DEVKIT_FLAGS} --ld-path=${BUILD_PREFIX}/bin/ld.lld -L${PREFIX}/lib/devkit/lib -L${PREFIX}/lib -Wl,-rpath-link,${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib"
test -d "${SYSROOT}"
test -x "${CC}"
unset LD_LIBRARY_PATH LD_PRELOAD ICU_DATA
export CXXFLAGS="${CXXFLAGS} -std=c++17"
# ICU invokes its newly built tools before installing them. Their dependencies
# live in the build tree; use RUNPATH rather than ICU's loader-env wrappers.
export LDFLAGS="${LDFLAGS} -L${PREFIX}/lib/devkit/lib/llvm-runtime -lgcc_s -Wl,-rpath,${SRC_DIR}/source/lib -Wl,-rpath,${SRC_DIR}/source/stubdata -Wl,-rpath,${SRC_DIR}/source/tools/ctestfw"
cp "${BUILD_PREFIX}/share/gnuconfig/config.guess" source/config.guess
cp "${BUILD_PREFIX}/share/gnuconfig/config.sub" source/config.sub
cd source
# Rattler-build may export a nonexistent host-prefix interpreter. With the
# test-data patch, ordinary discovery is harmless and no Python is invoked.
unset PYTHON
./configure --prefix="${PREFIX}" --disable-samples --disable-extras \
  --disable-tests
make -j"${CPU_COUNT}" INVOKE= PKGDATA_INVOKE= INSTALLED_INVOKE=
make install INVOKE= PKGDATA_INVOKE= INSTALLED_INVOKE=
mkdir -p "${PREFIX}/include/icu-${LIBRARY_VERSION}"
mv "${PREFIX}/include/unicode" "${PREFIX}/include/icu-${LIBRARY_VERSION}/"
# Adjust generated consumer metadata for the isolated headers and stage tools.
python3 - <<'PY'
import os
from pathlib import Path
prefix = Path(os.environ['PREFIX'])
version = os.environ['LIBRARY_VERSION']
for path in (prefix / 'lib/pkgconfig').glob('icu*.pc'):
    path.write_text(path.read_text().replace('${prefix}/include', '${prefix}/include/icu-' + version))
path = prefix / 'bin/icu-config'
text = path.read_text().replace('${prefix}/include', '${prefix}/include/icu-' + version)
lines = []
tools = {'CC': 'clang', 'CXX': 'clang++', 'AR': 'llvm-ar', 'RANLIB': 'llvm-ranlib'}
for line in text.splitlines():
    key = line.split('=', 1)[0]
    if key in tools:
        line = key + '="' + tools[key] + '"'
    lines.append(line)
path.write_text('\n'.join(lines) + '\n')
path = prefix / 'lib/icu' / version / 'Makefile.inc'
text = path.read_text().replace('$(prefix)/include', '$(prefix)/include/icu-' + version)
text = text.replace('${prefix}/include', '${prefix}/include/icu-' + version)
lines = []
for line in text.splitlines():
    key = line.split('=', 1)[0].strip()
    if key in tools:
        line = key + ' = ' + tools[key]
    elif key == 'CPP':
        line = 'CPP = clang -E'
    lines.append(line)
path.write_text('\n'.join(lines) + '\n')
path = prefix / 'lib/icu' / version / 'pkgdata.inc'
replacements = {
    'COMPILE': 'clang -O2 -c',
    'GENLIB': 'clang -shared -Wl,-Bsymbolic',
    'LIBFLAGS': '-I' + str(prefix / ('include/icu-' + version)) + ' -DPIC -fPIC',
    'AR': 'llvm-ar', 'RANLIB': 'llvm-ranlib',
}
lines = []
for line in path.read_text().splitlines():
    key = line.split('=', 1)[0]
    if key in replacements:
        line = key + '=' + replacements[key]
    lines.append(line)
path.write_text('\n'.join(lines) + '\n')
PY
# Post-link exception: ICU installs its build-tree tools without a separate install-time RUNPATH rewrite; pkgdata also invokes tools before installation.
# TODO: replace with target-specific upstream install/relink support.
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"
"${CXX}" ${CXXFLAGS} "${SRC_DIR}/devkit-tests/runtime.cpp" \
  -I"${PREFIX}/include/icu-${LIBRARY_VERSION}" ${LDFLAGS} \
  -licui18n -licuuc -licudata -o "${SRC_DIR}/icu-runtime-probe"
patchelf --set-rpath '$ORIGIN/runtime-lib' "${SRC_DIR}/icu-runtime-probe"

# Stage only this package's development interfaces; preserve runtime libraries.
python3 "${SRC_DIR}/devkit-build/stage-development.py" "${PREFIX}" --all
