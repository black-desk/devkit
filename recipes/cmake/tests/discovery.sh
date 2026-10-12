#!/usr/bin/env bash
set -euxo pipefail
# Unique fixtures avoid relying on which development packages the host has.
trap 'rm -f "${PREFIX}/lib/libdevkit-discovery.so" "${PREFIX}/include/devkit-discovery.h" "${PREFIX}/bin/devkit-discovery-tool"; rm -rf "${PREFIX}/lib/cmake/DevkitDiscovery"' EXIT
mkdir -p "${PREFIX}/lib/cmake/DevkitDiscovery" "${PREFIX}/include"
printf '%s\n' 'set(DevkitDiscovery_FOUND TRUE)' >"${PREFIX}/lib/cmake/DevkitDiscovery/DevkitDiscoveryConfig.cmake"
touch "${PREFIX}/lib/libdevkit-discovery.so" "${PREFIX}/include/devkit-discovery.h"
printf '%s\n' '#!/bin/sh' 'exit 0' >"${PREFIX}/bin/devkit-discovery-tool"
chmod +x "${PREFIX}/bin/devkit-discovery-tool"
mkdir -p discovery-alias
ln -sfn "${PREFIX}/bin" discovery-alias/bin
for entry in "${PREFIX}/bin/" "${PWD}/discovery-alias/bin"; do
  env -u CMAKE_PREFIX_PATH -u CMAKE_LIBRARY_PATH -u CMAKE_INCLUDE_PATH \
    PATH="${entry}:/usr/bin:/bin" "${PREFIX}/bin/cmake" \
    -S tests/discovery -B "${PWD}/discovery-default-${RANDOM}" -DEXPECT_CHANNEL=OFF
done
"${PREFIX}/bin/cmake" -S tests/discovery -B discovery-explicit \
  -DEXPECT_CHANNEL=ON -DEXPECT_PREFIX="${PREFIX}" -DCMAKE_PREFIX_PATH="${PREFIX}"
# Other PATH prefixes retain package discovery; model host library directories
# through CMAKE_SYSTEM_PREFIX_PATH without writing into /usr.
mkdir -p discovery-host/bin discovery-host/lib/cmake/DevkitDiscovery discovery-host/include
cp "${PREFIX}/lib/cmake/DevkitDiscovery/DevkitDiscoveryConfig.cmake" discovery-host/lib/cmake/DevkitDiscovery/
touch discovery-host/lib/libdevkit-discovery.so discovery-host/include/devkit-discovery.h
env -u CMAKE_PREFIX_PATH -u CMAKE_LIBRARY_PATH -u CMAKE_INCLUDE_PATH \
  PATH="${PREFIX}/bin:${PWD}/discovery-host/bin:/usr/bin:/bin" \
  "${PREFIX}/bin/cmake" -S tests/discovery -B discovery-host-build \
  -DEXPECT_CHANNEL=ON -DEXPECT_PREFIX="${PWD}/discovery-host" \
  -DCMAKE_SYSTEM_PREFIX_PATH="${PWD}/discovery-host"
