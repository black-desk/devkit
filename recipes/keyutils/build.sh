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
# Make expands $$ once; shell quotes preserve the literal loader token.
export LDFLAGS="${DEVKIT_FLAGS} --ld-path=${BUILD_PREFIX}/bin/ld.lld -L${PREFIX}/lib/devkit/lib -L${PREFIX}/lib -Wl,-rpath-link,${PREFIX}/lib"
test -d "${SYSROOT}"
test -x "${CC}"
NATIVE_LDFLAGS="${LDFLAGS} -Wl,--enable-new-dtags,-rpath,'\$\$ORIGIN:\$\$ORIGIN/../lib'"
args=(CC="${CC}" CXX="${CXX}" AR="${AR}"
  CFLAGS="${CFLAGS}" CXXFLAGS="${CXXFLAGS}" CPPFLAGS="${CPPFLAGS} -I."
  LDFLAGS="${NATIVE_LDFLAGS}"
  PREFIX="${PREFIX}" LIBDIR="${PREFIX}/lib" USRLIBDIR="${PREFIX}/lib"
  INCLUDEDIR="${PREFIX}/lib/devkit/include/keyutils-${LIBRARY_VERSION}"
  BINDIR="${PREFIX}/bin" SBINDIR="${PREFIX}/sbin"
  ETCDIR="${PREFIX}/etc" SHAREDIR="${PREFIX}/share/keyutils" MANDIR="${PREFIX}/share/man")
make -j"${CPU_COUNT}" "${args[@]}"
# As in the seed recipe, do not run the kernel/root-dependent integration suite
# in package builders. Validate the library's userspace ABI without keyring writes.
make "${args[@]}" install
"${CC}" ${CFLAGS} ${LDFLAGS} -I"${PREFIX}/lib/devkit/include/keyutils-${LIBRARY_VERSION}" \
  "${RECIPE_DIR}/tests/probe.c" "${PREFIX}/lib/libkeyutils.so" \
  '-Wl,--enable-new-dtags,-rpath,$ORIGIN/runtime-lib' -o library-probe
mkdir runtime-lib
ln -s "${PREFIX}/lib/libkeyutils.so.1" runtime-lib/libkeyutils.so.1
./library-probe

# Stage only this package's development interfaces; preserve runtime libraries.
python3 "${SRC_DIR}/devkit-build/stage-development.py" "${PREFIX}" --all
