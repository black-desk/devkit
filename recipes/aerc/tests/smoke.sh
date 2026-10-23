#!/usr/bin/env bash
set -euxo pipefail

carddav-query --help
aerc -v | grep -F 0.22.0
test -f "${PREFIX}/lib/devkit/share/aerc/aerc.conf"
test -f "${PREFIX}/lib/devkit/share/icons/hicolor/scalable/apps/aerc.svg"
test -f "${PREFIX}/lib/devkit/share/man/man5/aerc-notmuch.5"
test -x "${PREFIX}/lib/devkit/libexec/aerc/filters/colorize"
# The enabled backend must remain linked to this environment after relocation.
library="$(ldd "${PREFIX}/bin/aerc" | awk '$1 == "libnotmuch.so.5" { print $3 }')"
test "$(realpath "${library}")" = "$(realpath "${PREFIX}/lib/devkit/lib/libnotmuch.so.5")"

# Discover the default configuration through the relocated resource path.
# An explicit missing account file stops startup before terminal/network use.
export HOME="${PWD}/home"
export XDG_CONFIG_HOME="${HOME}/config"
export XDG_DATA_HOME="${HOME}/data"
export XDG_CACHE_HOME="${HOME}/cache"
missing_accounts="${PWD}/missing-accounts.conf"
if aerc -A "${missing_accounts}" >startup.log 2>&1; then
  echo 'aerc unexpectedly accepted the missing accounts file' >&2
  exit 1
fi
cmp "${XDG_CONFIG_HOME}/aerc/aerc.conf" "${PREFIX}/lib/devkit/share/aerc/aerc.conf"
grep -F "${missing_accounts}" startup.log

python3 tests/notmuch.py
