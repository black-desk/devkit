#!/usr/bin/env bash
set -euxo pipefail
mkdir -p "${PREFIX}/bin" "${PREFIX}/lib/devkit/share/ghcup"
install -m 0755 ghcup "${PREFIX}/bin/ghcup"
install -m 0644 LICENSE.upstream "${PREFIX}/lib/devkit/share/ghcup/LICENSE"
