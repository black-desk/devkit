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
unset LD_LIBRARY_PATH LD_PRELOAD ICU_DATA
export CXXFLAGS="${CXXFLAGS} -std=c++17"
# ICU runs newly built tools through its upstream loader-environment wrappers.
# Keep build-tree library paths out of the exported linker configuration.
export LDFLAGS="${LDFLAGS} -lgcc_s"
cp "${BUILD_PREFIX}/lib/devkit/share/gnuconfig/config.guess" source/config.guess
cp "${BUILD_PREFIX}/lib/devkit/share/gnuconfig/config.sub" source/config.sub
cd source
# Rattler-build may export a nonexistent host-prefix interpreter. With the
# test-data patch, ordinary discovery is harmless and no Python is invoked.
unset PYTHON
# This configuration uses the release production data, with tests disabled;
# skip-disabled-test-data.patch prevents a Python-only test-data dependency.
# The recipe test runtime probe covers selected APIs, not the ICU suite.
ICU_CONFIG_CC=clang ICU_CONFIG_CXX=clang++ ICU_CONFIG_CPP='clang -E' \
  ICU_CONFIG_AR=llvm-ar ICU_CONFIG_RANLIB=llvm-ranlib \
  ICU_CONFIG_CFLAGS=-O2 ICU_CONFIG_CXXFLAGS='-O2 -std=c++17' \
  ICU_CONFIG_CPPFLAGS='' ICU_CONFIG_LDFLAGS='' \
  ICU_CONFIG_PREFIX_RELATIVE=../../../../.. \
  ./configure --prefix="${PREFIX}" \
  --datarootdir="${PREFIX}/lib/devkit/share" \
  --libexecdir="${PREFIX}/lib/devkit/libexec" \
  --sysconfdir="${PREFIX}/lib/devkit/etc" \
  --localstatedir="${PREFIX}/lib/devkit/var" \
  --sbindir="${PREFIX}/lib/devkit/sbin" --libdir="${PREFIX}/lib/devkit/lib" --includedir="${PREFIX}/lib/devkit/include/icu-${LIBRARY_VERSION}" --disable-samples --disable-extras \
  --disable-tests
make -j"${CPU_COUNT}"
make install ICU_CONFIG_BINDIR="${PREFIX}/lib/devkit/libexec/icu/bin" \
  pkglibdir="${PREFIX}/lib/devkit/lib/icu/${LIBRARY_VERSION}"
# Post-link exception: ICU has no per-tool relative installed RUNPATH setting.
# Build-time tools use upstream loader wrappers; installed tools must load
# channel dependencies without those wrappers.
# TODO: replace with target-specific upstream install/relink support.
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"

# Seed tools retain public-library RPATH. Only dirty supplies runtime SONAME
# aliases for them; result/selfhost install exclusively in the private libdir.
if [[ "${SYSROOT_TRIPLET:-}" == x86_64-conda-linux-gnu ]]; then
  for library in "${PREFIX}/lib/devkit/lib/"libicudata.so.* "${PREFIX}/lib/devkit/lib/"libicui18n.so.* "${PREFIX}/lib/devkit/lib/"libicuio.so.* "${PREFIX}/lib/devkit/lib/"libicutest.so.* "${PREFIX}/lib/devkit/lib/"libicutu.so.* "${PREFIX}/lib/devkit/lib/"libicuuc.so.*; do
    [[ -f "${library}" ]] || continue
    soname="$(readelf -d "${library}" | sed -n 's/.*(SONAME).*\[\(.*\)\].*/\1/p')"
    [[ -n "${soname}" && "${soname}" != */* ]] || continue
    ln -sfn "devkit/lib/${soname}" "${PREFIX}/lib/${soname}"
  done
fi
