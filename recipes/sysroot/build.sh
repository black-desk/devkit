#!/usr/bin/env bash
set -euxo pipefail

: "${SYSROOT_TRIPLET:?rattler-build must provide sysroot_triplet}"

# Channel compiler configuration always uses this canonical layout. During
# seed builds, retain the seed triplet as a relative compatibility alias.
SYSROOT="${PREFIX}/x86_64-pc-linux-gnu/sysroot"
mkdir -p "${SYSROOT}"

extract_rpm() {
  local archive="$1" destination="$2"
  mkdir -p "${destination}"
  rpm2cpio "${archive}" | (cd "${destination}" && cpio -idm --quiet)
}

extract_rpm glibc.rpm binary-glibc
extract_rpm glibc-devel.rpm binary-glibc-devel
extract_rpm glibc-headers.rpm binary-glibc-headers
extract_rpm glibc-static.rpm binary-glibc-static
extract_rpm glibc-common.rpm binary-glibc-common
extract_rpm glibc-gconv-extra.rpm binary-glibc-gconv-extra
extract_rpm glibc-langpack-en.rpm binary-glibc-langpack-en
extract_rpm kernel-headers.rpm binary-kernel-headers

cd "${SYSROOT}"
cp -a "${SRC_DIR}/binary-glibc/." .
mkdir -p usr/include
cp -a "${SRC_DIR}/binary-glibc-devel/usr/." usr/
cp -a "${SRC_DIR}/binary-glibc-headers/usr/." usr/
cp -a "${SRC_DIR}/binary-glibc-static/usr/." usr/
cp -a "${SRC_DIR}/binary-glibc-common/usr/." usr/
cp -a "${SRC_DIR}/binary-glibc-gconv-extra/usr/." usr/
cp -a "${SRC_DIR}/binary-glibc-langpack-en/usr/." usr/
cp -a "${SRC_DIR}/binary-kernel-headers/usr/." usr/

# Preserve the RPM paths under /usr and Rocky's merged-/usr layout. These
# relative aliases are normally supplied by Rocky's filesystem RPM, rather
# than glibc; linker scripts still refer to /lib64.
# conda-forge reverses this layout for conda-build prefix detection:
# https://github.com/conda/conda-build/issues/5853
# We use rattler-build; the native layout passed local Clang/LLD link checks.
for directory in bin sbin lib lib64; do
  if [[ ! -e "${directory}" && ! -L "${directory}" ]]; then
    mkdir -p "usr/${directory}"
    ln -s "usr/${directory}" "${directory}"
  fi
done

# Follow conda-forge: do not let consumers auto-detect glibc's legacy
# libnsl.so.1, which is not guaranteed to exist on modern hosts. Packages
# needing NIS should depend on a separately packaged channel libnsl instead.
# https://github.com/conda-forge/rasterio-feedstock/issues/220
rm -f lib64/libnsl*.so* usr/lib64/libnsl.{a,so} || true
rm -f usr/include/rpcsvc/yp* usr/include/rpcsvc/yp*.h || true

# Omit documentation and system service integration from the sysroot.
rm -rf usr/share/man usr/share/doc usr/lib/systemd

# Reuse the tzdata runtime dependency instead of duplicating its database.
# From sysroot/usr/share, four parents reach PREFIX; keep the link relocatable.
mkdir -p usr/share
ln -s ../../../../share/zoneinfo usr/share/zoneinfo

# The conda-forge seed compiler uses x86_64-conda-linux-gnu. Let it access
# the canonical sysroot through a relative alias without duplicating files.
# Later stages use the canonical triplet and need no compatibility alias.
if [[ "${SYSROOT_TRIPLET}" != x86_64-pc-linux-gnu ]]; then
  ln -s x86_64-pc-linux-gnu "${PREFIX}/${SYSROOT_TRIPLET}"
fi
