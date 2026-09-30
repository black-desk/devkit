#!/usr/bin/env bash
set -euxo pipefail

: "${RUSTUP_VERSION:?rattler-build must provide RUSTUP_VERSION}"

test -f "${SRC_DIR}/rustup-init"
chmod 0755 "${SRC_DIR}/rustup-init"
test -x "${SRC_DIR}/rustup-init"
test -f "${SRC_DIR}/rustup-source/LICENSE-APACHE"
test -f "${SRC_DIR}/rustup-source/LICENSE-MIT"

binary_dir="${PREFIX}/lib/rustup/${RUSTUP_VERSION}"
license_dir="${PREFIX}/share/rustup"
mkdir -p "${binary_dir}" "${license_dir}" "${PREFIX}/bin"

# The official artifact behaves as rustup-init when invoked by that name and as
# the complete rustup manager when invoked as rustup.
install -m 0755 "${SRC_DIR}/rustup-init" "${binary_dir}/rustup-init"
ln -s "../lib/rustup/${RUSTUP_VERSION}/rustup-init" "${PREFIX}/bin/rustup"

install -m 0644 \
  "${SRC_DIR}/rustup-source/LICENSE-APACHE" \
  "${SRC_DIR}/rustup-source/LICENSE-MIT" \
  "${license_dir}/"
