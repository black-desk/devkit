#!/usr/bin/env bash
set -euxo pipefail
source "${SRC_DIR}/devkit-build/build-env.sh"
unset LD_LIBRARY_PATH LD_PRELOAD ICU_DATA
export CXXFLAGS="${CXXFLAGS} -std=c++17"
# ICU invokes its newly built tools before installing them. Their dependencies
# live in the build tree; use RUNPATH rather than ICU's loader-env wrappers.
export LDFLAGS="${LDFLAGS} -L${PREFIX}/lib/llvm-runtime -lgcc_s -Wl,-rpath,${SRC_DIR}/source/lib -Wl,-rpath,${SRC_DIR}/source/stubdata -Wl,-rpath,${SRC_DIR}/source/tools/ctestfw"
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
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"
"${CXX}" ${CXXFLAGS} "${SRC_DIR}/devkit-tests/runtime.cpp" \
  -I"${PREFIX}/include/icu-${LIBRARY_VERSION}" ${LDFLAGS} \
  -licui18n -licuuc -licudata -o "${SRC_DIR}/icu-runtime-probe"
patchelf --set-rpath '$ORIGIN/runtime-lib' "${SRC_DIR}/icu-runtime-probe"
