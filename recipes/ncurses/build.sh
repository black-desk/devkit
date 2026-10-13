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
# TODO: Remove the recipe-local LLD workaround when the version maps match
# every component/configuration. Keep split tinfo and versioned symbols enabled.
# https://github.com/NixOS/nixpkgs/pull/309887
# https://github.com/NixOS/nixpkgs/issues/310727
# https://lists.gnu.org/archive/html/bug-ncurses/2024-05/msg00086.html
export LDFLAGS="${LDFLAGS} -L${PREFIX}/lib/devkit/lib/llvm-runtime -lgcc_s -Wl,--undefined-version"
cp "${BUILD_PREFIX}/share/gnuconfig/config.guess" config.guess
cp "${BUILD_PREFIX}/share/gnuconfig/config.sub" config.sub
for mode in narrow wide; do
  wide_option=--disable-widec
  [[ "$mode" == narrow ]] || wide_option=--enable-widec
  ./configure --prefix="${PREFIX}" --includedir="${PREFIX}/include/ncurses-${LIBRARY_VERSION}" \
    --without-debug --without-ada --with-shared \
    --with-pkg-config --with-pkg-config-libdir="${PREFIX}/lib/pkgconfig" \
    --disable-overwrite --enable-symlinks --enable-termcap --enable-pc-files \
    --with-termlib --with-versioned-syms --disable-mixed-case \
    --enable-relative-terminfo "${wide_option}"
  make -j"${CPU_COUNT}"
  make install
  make distclean
done
# Normalize generated consumer metadata, without leaking seed compiler flags.
python3 - <<'PY'
import os
import re
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
            if '/include/ncurses-' + version not in line:
                line = line.replace('/include', '/include/ncurses-' + version)
        lines.append(line)
    path.write_text('\n'.join(lines) + '\n')
for path in (prefix / 'bin').glob('ncurses*6-config'):
    lines = []
    text = re.sub(r'(\$\{prefix\}|\$prefix)/include(?!/ncurses-' + re.escape(version) + r')',
                  r'\1/include/ncurses-' + version, path.read_text())
    for line in text.splitlines():
        if line.startswith('for opt in '):
            line = 'for opt in -L$libdir $LIBS'
        lines.append(line)
    path.write_text('\n'.join(lines) + '\n')
PY
# Post-link exception: narrow/wide builds install utilities and libraries with
# shared link flags; retain per-file paths until native install relinking is set.
# TODO: configure upstream target-specific install RUNPATH.
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"

# Stage only this package's development interfaces; preserve runtime libraries.
python3 "${SRC_DIR}/devkit-build/stage-development.py" "${PREFIX}" --all
