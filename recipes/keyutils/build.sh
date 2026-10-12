#!/usr/bin/env bash
set -euxo pipefail
source "${SRC_DIR}/devkit-build/build-env.sh"
args=(CC="${CC}" CXX="${CXX}" AR="${AR}"
  CFLAGS="${CFLAGS}" CXXFLAGS="${CXXFLAGS}" CPPFLAGS="${CPPFLAGS} -I."
  LDFLAGS="${LDFLAGS} -Wl,-rpath,${SRC_DIR}"
  PREFIX="${PREFIX}" LIBDIR="${PREFIX}/lib" USRLIBDIR="${PREFIX}/lib"
  INCLUDEDIR="${PREFIX}/include/keyutils-${LIBRARY_VERSION}"
  BINDIR="${PREFIX}/bin" SBINDIR="${PREFIX}/sbin"
  ETCDIR="${PREFIX}/etc" SHAREDIR="${PREFIX}/share/keyutils" MANDIR="${PREFIX}/share/man")
make -j"${CPU_COUNT}" "${args[@]}"
# As in the seed recipe, do not run the kernel/root-dependent integration suite
# in package builders. Validate the library's userspace ABI without keyring writes.
make "${args[@]}" install
python3 - <<'PY'
import os
from pathlib import Path
p = Path(os.environ['PREFIX']) / 'lib/pkgconfig/libkeyutils.pc'
lines = p.read_text().splitlines()
lines = ['prefix=${pcfiledir}/../..' if x.startswith('prefix=') else
         'exec_prefix=${prefix}' if x.startswith('exec_prefix=') else
         'libdir=${prefix}/lib' if x.startswith('libdir=') else
         'includedir=${prefix}/include/keyutils-' + os.environ['LIBRARY_VERSION']
         if x.startswith('includedir=') else x for x in lines]
p.write_text(('\n'.join(lines) + '\n').replace('-L${libdir} -lkeyutils', '${libdir}/libkeyutils.so'))
PY
"${CC}" ${CFLAGS} ${LDFLAGS} -I"${PREFIX}/include/keyutils-${LIBRARY_VERSION}" \
  "${RECIPE_DIR}/tests/probe.c" "${PREFIX}/lib/libkeyutils.so" \
  '-Wl,--enable-new-dtags,-rpath,$ORIGIN/runtime-lib' -o library-probe
mkdir runtime-lib
ln -s "${PREFIX}/lib/libkeyutils.so.1" runtime-lib/libkeyutils.so.1
./library-probe
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"
