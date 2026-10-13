#!/usr/bin/env bash
set -euxo pipefail
# Unique fixtures avoid relying on which development packages the host has.
trap 'rm -f "${PREFIX}/lib/devkit/lib/libdevkit-discovery.so" "${PREFIX}/lib/devkit/include/devkit-discovery.h" "${PREFIX}/bin/devkit-discovery-tool"; rm -rf "${PREFIX}/lib/devkit/lib/cmake/DevkitDiscovery"' EXIT
mkdir -p "${PREFIX}/lib/devkit/lib/cmake/DevkitDiscovery" "${PREFIX}/lib/devkit/include"
printf '%s\n' 'set(DevkitDiscovery_FOUND TRUE)' >"${PREFIX}/lib/devkit/lib/cmake/DevkitDiscovery/DevkitDiscoveryConfig.cmake"
touch "${PREFIX}/lib/devkit/lib/libdevkit-discovery.so" "${PREFIX}/lib/devkit/include/devkit-discovery.h"
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
  -DEXPECT_CHANNEL=ON -DEXPECT_PREFIX="${PREFIX}/lib/devkit" -DCMAKE_PREFIX_PATH="${PREFIX}/lib/devkit"
# Other PATH prefixes retain package discovery; model host library directories
# through CMAKE_SYSTEM_PREFIX_PATH without writing into /usr.
mkdir -p discovery-host/bin discovery-host/lib/cmake/DevkitDiscovery discovery-host/include
cp "${PREFIX}/lib/devkit/lib/cmake/DevkitDiscovery/DevkitDiscoveryConfig.cmake" discovery-host/lib/cmake/DevkitDiscovery/
touch discovery-host/lib/libdevkit-discovery.so discovery-host/include/devkit-discovery.h
env -u CMAKE_PREFIX_PATH -u CMAKE_LIBRARY_PATH -u CMAKE_INCLUDE_PATH \
  PATH="${PREFIX}/bin:${PWD}/discovery-host/bin:/usr/bin:/bin" \
  "${PREFIX}/bin/cmake" -S tests/discovery -B discovery-host-build \
  -DEXPECT_CHANNEL=ON -DEXPECT_PREFIX="${PWD}/discovery-host" \
  -DCMAKE_SYSTEM_PREFIX_PATH="${PWD}/discovery-host"
