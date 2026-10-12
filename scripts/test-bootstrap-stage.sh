#!/usr/bin/env bash
set -euo pipefail
unset LD_LIBRARY_PATH LD_PRELOAD
if (($# != 2)); then
  echo 'usage: test-bootstrap-stage.sh CHANNEL PACKAGE_MANIFEST' >&2
  exit 2
fi
CHANNEL="$(cd -- "$1" && pwd)"
MANIFEST="$2"
RBT="${RATTLER_BUILD:-rattler-build}"
[[ -s "$MANIFEST" ]] || { echo 'error: empty stage package manifest' >&2; exit 1; }
# Check the entire manifest before starting any package test.
while IFS= read -r archive; do
  [[ "$archive" =~ ^(linux-64|noarch)/[^/]+\.conda$ && -f "$CHANNEL/$archive" ]] || {
    echo "error: invalid or missing stage archive: $archive" >&2
    exit 1
  }
done < "$MANIFEST"
while IFS= read -r archive; do
  "$RBT" test --package-file "$CHANNEL/$archive" \
    --channel "$CHANNEL" --channel-priority strict --no-config
done < "$MANIFEST"
