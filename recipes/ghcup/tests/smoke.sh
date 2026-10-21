#!/usr/bin/env bash
set -euxo pipefail
export GHCUP_USE_XDG_DIRS=1
export XDG_DATA_HOME="${PWD}/ghcup-state/data"
export XDG_CACHE_HOME="${PWD}/ghcup-state/cache"
export XDG_CONFIG_HOME="${PWD}/ghcup-state/config"
export XDG_BIN_HOME="${PWD}/ghcup-state/bin"
export GHCUP_SKIP_UPDATE_CHECK=1
mkdir -p "${XDG_DATA_HOME}"
test "$(ghcup --numeric-version)" = 0.2.6.2
ghcup --offline --help >help.txt
grep -F 'GHC/cabal/HLS/stack' help.txt
test ! -e "${XDG_DATA_HOME}/ghcup/ghc"
python3 -c 'import json, os; from pathlib import Path; d=json.loads((Path(os.environ["PREFIX"])/"etc/conda/env_vars.d/ghcup.json").read_text()); assert d == {"GHCUP_USE_XDG_DIRS":"1", "GHCUP_SKIP_UPDATE_CHECK":"1"}'
# The imported upstream Linux manager must not acquire host GNU runtimes.
readelf -d "${PREFIX}/bin/ghcup" >dynamic.txt
grep -F 'There is no dynamic section' dynamic.txt
