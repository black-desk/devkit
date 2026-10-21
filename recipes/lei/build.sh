#!/usr/bin/env bash
set -euxo pipefail

export PATH="${BUILD_PREFIX}/bin:${PATH}"
export CC="${BUILD_PREFIX}/bin/clang"
export CXX="${BUILD_PREFIX}/bin/clang++"
export AR="${BUILD_PREFIX}/bin/llvm-ar"
export RANLIB="${BUILD_PREFIX}/bin/llvm-ranlib"
export NM="${BUILD_PREFIX}/bin/llvm-nm"
export STRIP="${BUILD_PREFIX}/bin/llvm-strip"
export CFLAGS="--no-default-config --config=${BUILD_PREFIX}/lib/devkit/share/devkit/clang.cfg -O2 -fPIC"
export CXXFLAGS="${CFLAGS}"
export CPPFLAGS=""
export LDFLAGS="--no-default-config --config=${BUILD_PREFIX}/lib/devkit/share/devkit/clang.cfg -L${PREFIX}/lib/devkit/lib -Wl,-rpath-link,${PREFIX}/lib/devkit/lib -Wl,--enable-new-dtags,-rpath,${PREFIX}/lib/devkit/lib"
export PKG_CONFIG="${BUILD_PREFIX}/bin/pkg-config"
export PKG_CONFIG_LIBDIR="${PREFIX}/lib/devkit/lib/pkgconfig"
export PKG_CONFIG_PATH="${PKG_CONFIG_LIBDIR}"

private="${PREFIX}/lib/devkit/lib/perl-tools/lei"
export PERL5LIB="${private}/lib/perl5"
mkdir -p "${SRC_DIR}/licenses"
for module in DBI DBD-SQLite Devel-Leak Search-Xapian MIME-Base32 Test-Needs Test-Warnings URI Email-Address-XS Socket-MsgHdr; do
  (
    cd "${SRC_DIR}/cpan/${module}"
    # Use the merged-prefix Perl Config unchanged, including its Clang setup.
    perl Makefile.PL INSTALL_BASE="${private}" \
      XAPIAN_CONFIG="${PREFIX}/lib/devkit/libexec/xapian/bin/xapian-config"
    make -j"${CPU_COUNT}"
    make test
    make install
    mkdir -p "${SRC_DIR}/licenses/${module}"
    find . -maxdepth 1 -type f \( -iname '*license*' -o -iname '*copying*' -o -iname '*artistic*' -o -name README \) \
      -exec cp '{}' "${SRC_DIR}/licenses/${module}/" \;
  )
done
perl Makefile.PL INSTALL_BASE="${private}"
make -j"${CPU_COUNT}"
make install
# The public package promises lei; server commands remain private.
mkdir -p "${PREFIX}/bin"
sed "1c\\#!${PREFIX}/bin/perl" "${RECIPE_DIR}/lei" >"${PREFIX}/bin/lei"
chmod 755 "${PREFIX}/bin/lei"
cp COPYING "${SRC_DIR}/licenses/public-inbox-COPYING"

# Post-link exception: CPAN MakeMaker extensions use the installed Perl linker configuration.
# Normalize newly installed ELF to relative channel RUNPATH.
# TODO: upstream separate build/install RUNPATH support.
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"
