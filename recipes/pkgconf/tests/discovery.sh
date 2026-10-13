#!/usr/bin/env bash
set -euxo pipefail
fixture="${PREFIX}/lib/devkit/lib/pkgconfig/devkit-discovery.pc"
trap 'rm -f "${fixture}"' EXIT
mkdir -p "${PREFIX}/lib/devkit/lib/pkgconfig"
printf '%s\n' 'Name: devkit-discovery' 'Description: default discovery probe' 'Version: 1.0' >"${fixture}"
if env -u PKG_CONFIG_PATH -u PKG_CONFIG_LIBDIR "${PREFIX}/bin/pkgconf" --exists devkit-discovery; then
  echo 'Default pkgconf search included channel metadata' >&2
  exit 1
fi
PKG_CONFIG_LIBDIR="${PREFIX}/lib/devkit/lib/pkgconfig" "${PREFIX}/bin/pkgconf" --exists devkit-discovery
PKG_CONFIG_PATH="${PREFIX}/lib/devkit/lib/pkgconfig" "${PREFIX}/bin/pkgconf" --exists devkit-discovery
pc_path="$(env -u PKG_CONFIG_PATH -u PKG_CONFIG_LIBDIR "${PREFIX}/bin/pkgconf" --variable=pc_path pkg-config)"
case ":${pc_path}:" in
  *":${PREFIX}/"*) exit 1 ;;
esac
case ":${pc_path}:" in
  *:/usr/lib/x86_64-linux-gnu/pkgconfig:*) ;;
  *) exit 1 ;;
esac
