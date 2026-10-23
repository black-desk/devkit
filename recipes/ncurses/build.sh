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
  DEVKIT_FLAGS="--no-default-config --config=${BUILD_PREFIX}/lib/devkit/share/devkit/clang.cfg"
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
export LDFLAGS="${DEVKIT_FLAGS} --ld-path=${BUILD_PREFIX}/bin/ld.lld -L${PREFIX}/lib/devkit/lib -Wl,-rpath-link,${PREFIX}/lib/devkit/lib -Wl,-rpath,${PREFIX}/lib/devkit/lib"
test -d "${SYSROOT}"
test -x "${CC}"
# TODO: Remove the recipe-local LLD workaround when the version maps match
# every component/configuration. Keep split tinfo and versioned symbols enabled.
# https://github.com/NixOS/nixpkgs/pull/309887
# https://github.com/NixOS/nixpkgs/issues/310727
# https://lists.gnu.org/archive/html/bug-ncurses/2024-05/msg00086.html
export LDFLAGS="${LDFLAGS} -lgcc_s -Wl,--undefined-version"
cp "${BUILD_PREFIX}/lib/devkit/share/gnuconfig/config.guess" config.guess
cp "${BUILD_PREFIX}/lib/devkit/share/gnuconfig/config.sub" config.sub
for mode in narrow wide; do
  wide_option=--disable-widec
  [[ "$mode" == narrow ]] || wide_option=--enable-widec
  header_subdir=ncurses
  [[ "$mode" == narrow ]] || header_subdir=ncursesw
  # Mixed-case terminfo uses x/xterm rather than 78/xterm, matching Linux host
  # databases so TERMINFO can select host entries such as xterm-ghostty.
  ./configure --prefix="${PREFIX}" \
    --datarootdir="${PREFIX}/lib/devkit/share" \
    --libexecdir="${PREFIX}/lib/devkit/libexec" \
    --sysconfdir="${PREFIX}/lib/devkit/etc" \
    --localstatedir="${PREFIX}/lib/devkit/var" \
    --sbindir="${PREFIX}/lib/devkit/sbin" --libdir="${PREFIX}/lib/devkit/lib" --includedir="${PREFIX}/lib/devkit/include/ncurses-6.6/${header_subdir}" \
    --without-debug --without-ada --with-shared --disable-pkg-ldflags \
    --with-pkg-config --with-pkg-config-libdir="${PREFIX}/lib/devkit/lib/pkgconfig" \
    --disable-overwrite --enable-symlinks --enable-termcap --enable-pc-files \
    --with-termlib --with-versioned-syms --enable-mixed-case \
    --enable-relative-terminfo "${wide_option}"
  make -j"${CPU_COUNT}"
  make install CONFIG_BINDIR="${PREFIX}/lib/devkit/libexec/ncurses/bin"
  make distclean
done
# Post-link exception: narrow/wide builds install utilities and libraries with
# shared link flags; retain per-file paths until native install relinking is set.
# TODO: configure upstream target-specific install RUNPATH.
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"

# Seed tools retain public-library RPATH. Only dirty supplies runtime SONAME
# aliases for them; result/selfhost install exclusively in the private libdir.
if [[ "${SYSROOT_TRIPLET:-}" == x86_64-conda-linux-gnu ]]; then
  for library in "${PREFIX}/lib/devkit/lib/"libform.so.* "${PREFIX}/lib/devkit/lib/"libformw.so.* "${PREFIX}/lib/devkit/lib/"libmenu.so.* "${PREFIX}/lib/devkit/lib/"libmenuw.so.* "${PREFIX}/lib/devkit/lib/"libncurses.so.* "${PREFIX}/lib/devkit/lib/"libncurses++.so.* "${PREFIX}/lib/devkit/lib/"libncurses++w.so.* "${PREFIX}/lib/devkit/lib/"libncursesw.so.* "${PREFIX}/lib/devkit/lib/"libpanel.so.* "${PREFIX}/lib/devkit/lib/"libpanelw.so.* "${PREFIX}/lib/devkit/lib/"libtinfo.so.* "${PREFIX}/lib/devkit/lib/"libtinfow.so.*; do
    [[ -f "${library}" ]] || continue
    soname="$(readelf -d "${library}" | sed -n 's/.*(SONAME).*\[\(.*\)\].*/\1/p')"
    [[ -n "${soname}" && "${soname}" != */* ]] || continue
    ln -sfn "devkit/lib/${soname}" "${PREFIX}/lib/${soname}"
  done
fi
