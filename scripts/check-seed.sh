#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CHANNEL="$ROOT/channels/seed"
for tool in mamba jq; do command -v "$tool" >/dev/null || { echo "error: required tool not found: $tool" >&2; exit 1; }; done
for subdir in linux-64 noarch; do [[ -f "$CHANNEL/$subdir/repodata.json" ]] || { echo "error: missing $subdir repodata" >&2; exit 1; }; done
expected_count="$(grep -c '^' "$ROOT/seed-packages.tsv")"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
CONDA_PKGS_DIRS="$tmp/pkgs" mamba create --prefix "$tmp/prefix" --dry-run --json --offline --override-channels --channel "file://$CHANNEL" --platform linux-64 \
  clang-23=23.1.3 llvm-tools=23.1.3 lld=23.1.2 cmake=3.31.8 ninja=1.13.2 \
  sysroot_linux-64=2.28 make=4.4.1 gnuconfig=2025.07.09 gettext-tools=0.25.1 perl=5.44.0 libxcrypt=4.4.38 \
  libgcc-devel_linux-64=16.2.0 libstdcxx-devel_linux-64=16.2.0 >"$tmp/result.json"
jq -e '.success == true' "$tmp/result.json" >/dev/null || { echo 'error: offline local-channel solve failed' >&2; exit 1; }
resolved_count="$(jq '.actions.LINK | length' "$tmp/result.json")"
[[ "$resolved_count" == "$expected_count" ]] || { echo "error: expected $expected_count packages, resolved $resolved_count" >&2; exit 1; }
declare -A required=([clang-23]=1 [llvm-tools]=1 [lld]=1 [cmake]=1 [ninja]=1 [sysroot_linux-64]=1 [make]=1 [gnuconfig]=1 [gettext-tools]=1 [perl]=1 [libxcrypt]=1)
while IFS= read -r name; do unset 'required[$name]'; done < <(jq -r '.actions.LINK[].name' "$tmp/result.json")
if ((${#required[@]})); then echo "error: missing required packages: ${!required[*]}" >&2; exit 1; fi
jq -e '[.actions.LINK[].name | select(
  . == "gcc" or . == "gxx" or . == "gcc_impl_linux-64" or . == "gxx_impl_linux-64" or
  . == "binutils" or . == "binutils_impl_linux-64" or . == "ld_impl_linux-64"
)] | length == 0' "$tmp/result.json" >/dev/null || {
  echo 'error: the Clang seed must not contain a GCC compiler or GNU binutils' >&2
  exit 1
}
while IFS= read -r url; do [[ "$url" == "file://$CHANNEL/"* ]] || { echo "error: package came from outside local channel: $url" >&2; exit 1; }; done < <(jq -r '.actions.LINK[].url // ""' "$tmp/result.json")
echo "offline local-channel solve: OK ($resolved_count packages)"
