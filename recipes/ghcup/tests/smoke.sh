#!/usr/bin/env bash
set -euxo pipefail
unset GHCUP_USE_XDG_DIRS
export GHCUP_INSTALL_BASE_PREFIX="${PWD}/ghcup-state"
export GHCUP_SKIP_UPDATE_CHECK=1
mkdir -p "${GHCUP_INSTALL_BASE_PREFIX}"
test "$(ghcup --numeric-version)" = 0.2.6.2
ghcup --offline --help >help.txt
grep -F 'GHC/cabal/HLS/stack' help.txt
# Empty local metadata lets debug-info run offline without downloading a catalog.
mkdir -p "${GHCUP_INSTALL_BASE_PREFIX}/.ghcup/cache"
printf 'toolRequirements: {}\nghcupDownloads: {}\n' >"${GHCUP_INSTALL_BASE_PREFIX}/.ghcup/cache/ghcup-0.1.0.yaml"
ghcup --offline debug-info >directories.txt
grep -F "${GHCUP_INSTALL_BASE_PREFIX}/.ghcup" directories.txt
test -z "$(find "${GHCUP_INSTALL_BASE_PREFIX}/.ghcup/ghc" -mindepth 1 -print -quit)"
test ! -e "${PREFIX}/etc/conda/env_vars.d/ghcup.json"
# The imported upstream Linux manager must not acquire host GNU runtimes.
readelf -d "${PREFIX}/bin/ghcup" >dynamic.txt
grep -F 'There is no dynamic section' dynamic.txt
