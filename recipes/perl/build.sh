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

: "${PERL_VERSION:?rattler-build must provide PERL_VERSION}"
: "${SYSROOT_TRIPLET:?rattler-build must provide SYSROOT_TRIPLET}"

: "${BUILD_PREFIX:?}"
: "${PREFIX:?}"
# Keep compiler paths in the prefix tracked by Conda's text relocation.
test "${BUILD_PREFIX}" = "${PREFIX}"
export SYSROOT="${BUILD_PREFIX}/${SYSROOT_TRIPLET:-x86_64-pc-linux-gnu}/sysroot"
export CC="${BUILD_PREFIX}/bin/clang"
export CXX="${BUILD_PREFIX}/bin/clang++"
if [[ "${SYSROOT_TRIPLET:-}" == x86_64-conda-linux-gnu ]]; then
  # Use seed-owned names directly. New aliases in this merged prefix would be
  # collected as Perl payload, and its recorded compiler must survive install.
  export CC="${BUILD_PREFIX}/bin/clang-23"
  export CXX="${BUILD_PREFIX}/bin/clang++-23"
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
  # clang.cfg already selects libc++ headers; adding them again breaks the
  # C wrapper headers' include_next search.
  export CXXFLAGS="${CFLAGS}"
fi
export CPPFLAGS="${DEVKIT_FLAGS}"
export LDFLAGS="${DEVKIT_FLAGS} --ld-path=${BUILD_PREFIX}/bin/ld.lld -L${PREFIX}/lib/devkit/lib -Wl,-rpath-link,${PREFIX}/lib/devkit/lib -Wl,-rpath,${PREFIX}/lib/devkit/lib"
test -d "${SYSROOT}"
test -x "${CC}"
# Linux hints otherwise query /usr/bin/gcc and may discover host DB/crypt.
# Set the supported discovery overrides explicitly for both compiler variants.
PERL_LIBRARY_PATH="${PREFIX}/lib/devkit/lib ${SYSROOT}/lib64"
COMMON_CFLAGS="${CFLAGS} -I${PREFIX}/lib/devkit/include/libxcrypt-4.4.38"

PERL_CFLAGS="${COMMON_CFLAGS} -D_REENTRANT -D_GNU_SOURCE -fwrapv -fno-strict-aliasing -fstack-protector-strong -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64"

# installstyle only selects lib versus lib/perl5; it is not a directory.
# Perl INSTALL documents .../ as relative to the interpreter directory.
# Keep relocatable @INC; Configure derives archlib/sitearch and install paths.
./Configure \
  -de \
  -Dprefix="${PREFIX}" \
  -Duserelocatableinc \
  -Dinstallstyle=lib/perl5 \
  -Dprivlib=".../../lib/devkit/lib/perl5/${PERL_VERSION}" \
  -Dsitelib=".../../lib/devkit/lib/perl5/site_perl/${PERL_VERSION}" \
  -Dinstallusrbinperl=n \
  -Dusethreads \
  -Dinc_version_list=none \
  -Dcc="${CC}" \
  -Dcppstdin="${CC} ${PERL_CFLAGS} -E" \
  -Dcppminus=- \
  -Dcpprun="${CC} ${PERL_CFLAGS} -E" \
  -Dcpplast=- \
  -Dld="${CC}" \
  -Dar="${AR}" \
  -Dranlib="${RANLIB}" \
  -Dccflags="${PERL_CFLAGS}" \
  -Dldflags="${LDFLAGS}" \
  -Dlddlflags="-shared ${LDFLAGS}" \
  -Dcccdlflags="-fPIC" \
  -Dsysroot="${SYSROOT}" \
  -Dlibpth="${PERL_LIBRARY_PATH}" \
  -Dplibpth="${PERL_LIBRARY_PATH}" \
  -Dglibpth="${PERL_LIBRARY_PATH}" \
  -Dloclibpth="${PREFIX}/lib/devkit/lib" \
  -Dxlibpth=" " \
  -Dmalloctype='void *' \
  -Dfreetype=void \
  -Dmyhostname=devkit \
  -Dmydomain=.invalid \
  -Dperladmin=devkit@invalid \
  -Dcf_by=black-desk \
  -Dcf_email=devkit@invalid \
  -Dman1dir=none \
  -Dman3dir=none

make -j"${CPU_COUNT}"

# GNU env 9.12 quotes values containing shell metacharacters, while Perl's
# environment tests expect the traditional raw format. Prefer the runner's
# /usr/bin/env for the selected tests while retaining channel compiler tools.
TEST_PATH="${BUILD_PREFIX}/bin:/usr/bin:/bin"
if [[ "${DEVKIT_RUN_TESTS:-1}" == 1 ]]; then
  PATH="${TEST_PATH}" make test_harness \
    HARNESS_OPTIONS="j${CPU_COUNT}" \
    TEST_ARGS='op/magic.t op/tie.t ../lib/perl5db.t'
fi

# Install the original Config modules. The merged prefix lets rattler-build
# record their tool paths for normal Conda prefix replacement on installation.
make install -j"${CPU_COUNT}"

# Preserve relocatable DT_RUNPATH; package tests run without loader overrides.
# Post-link exception: Perl applies one lddlflags value to XS modules installed at different depths; its relocatable-inc support does not compute per-module RUNPATH.
# TODO: replace with target-specific upstream install/relink support.
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"
