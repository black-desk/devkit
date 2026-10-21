#!/usr/bin/env bash
set -euxo pipefail
mkdir -p "${PREFIX}/bin" "${PREFIX}/lib/devkit/share/ghcup"
install -m 0755 ghcup "${PREFIX}/bin/ghcup"
install -m 0644 LICENSE.upstream "${PREFIX}/lib/devkit/share/ghcup/LICENSE"
# GHCup uses its upstream user directories; no GHC/Cabal/HLS is installed here.
mkdir -p "${PREFIX}/etc/conda/env_vars.d"
cat >"${PREFIX}/etc/conda/env_vars.d/ghcup.json" <<'EOF'
{"GHCUP_USE_XDG_DIRS": "1", "GHCUP_SKIP_UPDATE_CHECK": "1"}
EOF
