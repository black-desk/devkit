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
cp "${BUILD_PREFIX}/lib/devkit/share/gnuconfig/"config.* src/config/
export PKG_CONFIG="${BUILD_PREFIX}/bin/pkgconf"
export PKG_CONFIG_LIBDIR="${PREFIX}/lib/devkit/lib/pkgconfig"
unset PKG_CONFIG_PATH
export CPPFLAGS="${CPPFLAGS} -I${PREFIX}/lib/devkit/include/openssl-3.5.9 -I${PREFIX}/lib/devkit/include/keyutils-1.6.3"
export LDFLAGS="${LDFLAGS} -lgcc_s -Wl,-rpath,${SRC_DIR}/src/lib"
cd src
# MIT's official release includes configure; unlike the Git snapshot used by
# forge, it does not require autoreconf. Keep forge's native feature baseline.
# Explicit NLS makes a missing msgfmt an error instead of silently dropping it.
./configure --prefix="${PREFIX}" \
  --datarootdir="${PREFIX}/lib/devkit/share" \
  --libexecdir="${PREFIX}/lib/devkit/libexec" \
  --sysconfdir="${PREFIX}/lib/devkit/etc" \
  --localstatedir="${PREFIX}/lib/devkit/var" \
  --sbindir="${PREFIX}/lib/devkit/sbin" --libdir="${PREFIX}/lib/devkit/lib" --includedir="${PREFIX}/lib/devkit/include/krb5-${LIBRARY_VERSION}" \
  --without-tcl --without-readline --with-libedit --with-crypto-impl=openssl \
  --with-keyutils=yes --without-system-verto --enable-nls
make -j"${CPU_COUNT}"
# MIT Makefiles use PKGCONFIG_DIR, unlike Automake's pkgconfigdir.
make install PKGCONFIG_DIR="${PREFIX}/lib/devkit/lib/pkgconfig"
cd ..
# Post-link exception: MIT Makefiles use the same LDFLAGS for in-tree tools and installed ELF files at multiple directory depths.
# TODO: replace with target-specific upstream install/relink support.
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"

# Native directory options do not cover these consumer-tool details.
python3 "${RECIPE_DIR}/relocate-development.py"

# Seed tools retain public-library RPATH. Only dirty supplies runtime SONAME
# aliases for them; result/selfhost install exclusively in the private libdir.
if [[ "${SYSROOT_TRIPLET:-}" == x86_64-conda-linux-gnu ]]; then
  for library in "${PREFIX}/lib/devkit/lib/"libcom_err.so.* "${PREFIX}/lib/devkit/lib/"libgssapi_krb5.so.* "${PREFIX}/lib/devkit/lib/"libgssrpc.so.* "${PREFIX}/lib/devkit/lib/"libk5crypto.so.* "${PREFIX}/lib/devkit/lib/"libkadm5clnt.so.* "${PREFIX}/lib/devkit/lib/"libkadm5clnt_mit.so.* "${PREFIX}/lib/devkit/lib/"libkadm5srv.so.* "${PREFIX}/lib/devkit/lib/"libkadm5srv_mit.so.* "${PREFIX}/lib/devkit/lib/"libkdb5.so.* "${PREFIX}/lib/devkit/lib/"libkrad.so.* "${PREFIX}/lib/devkit/lib/"libkrb5.so.* "${PREFIX}/lib/devkit/lib/"libkrb5support.so.* "${PREFIX}/lib/devkit/lib/"libverto.so.*; do
    [[ -f "${library}" ]] || continue
    soname="$(readelf -d "${library}" | sed -n 's/.*(SONAME).*\[\(.*\)\].*/\1/p')"
    [[ -n "${soname}" && "${soname}" != */* ]] || continue
    ln -sfn "devkit/lib/${soname}" "${PREFIX}/lib/${soname}"
  done
fi
