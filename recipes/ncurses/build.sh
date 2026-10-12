#!/usr/bin/env bash
set -euxo pipefail
source "${SRC_DIR}/devkit-build/build-env.sh"
# TODO: Remove the recipe-local LLD workaround when the version maps match
# every component/configuration. Keep split tinfo and versioned symbols enabled.
# https://github.com/NixOS/nixpkgs/pull/309887
# https://github.com/NixOS/nixpkgs/issues/310727
# https://lists.gnu.org/archive/html/bug-ncurses/2024-05/msg00086.html
export LDFLAGS="${LDFLAGS} -L${PREFIX}/lib/llvm-runtime -lgcc_s -Wl,--undefined-version"
cp "${BUILD_PREFIX}/share/gnuconfig/config.guess" config.guess
cp "${BUILD_PREFIX}/share/gnuconfig/config.sub" config.sub
for mode in narrow wide; do
  wide_option=--disable-widec
  [[ "$mode" == narrow ]] || wide_option=--enable-widec
  ./configure --prefix="${PREFIX}" \
    --without-debug --without-ada --with-shared \
    --with-pkg-config --with-pkg-config-libdir="${PREFIX}/lib/pkgconfig" \
    --disable-overwrite --enable-symlinks --enable-termcap --enable-pc-files \
    --with-termlib --with-versioned-syms --disable-mixed-case \
    --enable-relative-terminfo "${wide_option}"
  make -j"${CPU_COUNT}"
  make install
  make distclean
done
mkdir -p "${PREFIX}/include/ncurses-${LIBRARY_VERSION}"
for header in "${PREFIX}/include/"*; do
  [[ "${header}" == "${PREFIX}/include/ncurses-${LIBRARY_VERSION}" ]] && continue
  mv "${header}" "${PREFIX}/include/ncurses-${LIBRARY_VERSION}/"
done
# Normalize generated consumer metadata, without leaking seed compiler flags.
python3 - <<'PY'
import os
from pathlib import Path
prefix = Path(os.environ['PREFIX'])
version = os.environ['LIBRARY_VERSION']
for path in (prefix / 'lib/pkgconfig').glob('*.pc'):
    lines = []
    for line in path.read_text().splitlines():
        if line.startswith('Libs:'):
            libraries = [flag for flag in line.split()[1:]
                         if flag.startswith('-l') and flag != '-lgcc_s']
            line = 'Libs: -L${libdir} ' + ' '.join(libraries)
        elif line.startswith('Cflags:'):
            definitions = [flag for flag in line.split()[1:] if flag.startswith('-D')]
            line = ('Cflags: ' + ' '.join(definitions)
                    + ' -I${includedir} -I${prefix}/include/ncurses-' + version)
        elif line.startswith('includedir='):
            line = line.replace('/include', '/include/ncurses-' + version)
        lines.append(line)
    path.write_text('\n'.join(lines) + '\n')
for path in (prefix / 'bin').glob('ncurses*6-config'):
    lines = []
    text = path.read_text().replace('${prefix}/include', '${prefix}/include/ncurses-' + version)
    text = text.replace('$prefix/include', '$prefix/include/ncurses-' + version)
    for line in text.splitlines():
        if line.startswith('for opt in '):
            line = 'for opt in -L$libdir $LIBS'
        lines.append(line)
    path.write_text('\n'.join(lines) + '\n')
PY
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"
