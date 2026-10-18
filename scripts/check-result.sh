#!/usr/bin/env bash
set -euo pipefail
unset LD_LIBRARY_PATH LD_PRELOAD
ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CLOSURE_ONLY=0
if [[ "${1:-}" == --closure-only ]]; then
  CLOSURE_ONLY=1
  shift
fi
CHANNEL="$(cd -- "${1:-$ROOT/channels/result}" && pwd)"
for tool in mamba jq; do command -v "$tool" >/dev/null || {
  echo "error: required tool not found: $tool" >&2
  exit 1
}; done
for subdir in linux-64 noarch; do [[ -f "$CHANNEL/$subdir/repodata.json" ]] || {
  echo "error: missing $subdir repodata" >&2
  exit 1
}; done
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
CONDA_PKGS_DIRS="$tmp/pkgs" mamba create --prefix "$tmp/prefix" --dry-run --json --offline --override-channels --channel "file://$CHANNEL" --strict-channel-priority --platform linux-64 sysroot_linux-64 clang llvm-libgcc libcxx make perl pkgconf openssl ca-certificates ninja cmake gnuconfig gettext gettext-tools krb5 libssh2 libnghttp2 curl libcurl expat libexpat lzo lz4-c libarchive jsoncpp cppdap bzip2 libuv rhash c-ares keyutils libev libedit zlib libzlib zstd ncurses libiconv liblzma icu libpsl libxml2 libxml2-16 libxcrypt >"$tmp/result.json"
jq -e '.success == true' "$tmp/result.json" >/dev/null || {
  echo 'error: stage-only solve failed' >&2
  exit 1
}
expected_names=$'bzip2\nc-ares\nca-certificates\nclang\ncmake\ncppdap\ncurl\nexpat\ngettext\ngettext-tools\ngnuconfig\nicu\njsoncpp\nkeyutils\nkrb5\nlibarchive\nlibcurl\nlibcxx\nlibedit\nlibev\nlibexpat\nlibiconv\nliblzma\nlibnghttp2\nlibpsl\nlibssh2\nlibuv\nlibxml2\nlibxml2-16\nlibxcrypt\nlibzlib\nllvm-libgcc\nlz4-c\nlzo\nmake\nncurses\nninja\nopenssl\nperl\npkgconf\nrhash\nsysroot_linux-64\ntzdata\nzlib\nzstd'
# Compare package sets with stable collation across developer/CI locales.
expected_names="$(printf '%s\n' "$expected_names" | LC_ALL=C sort -u)"
actual_names="$(jq -r '.actions.LINK[].name' "$tmp/result.json" | LC_ALL=C sort -u)"
[[ "$actual_names" == "$expected_names" ]] || {
  echo "error: expected package set [$expected_names], got [$actual_names]" >&2
  exit 1
}
while IFS=$'\t' read -r name channel_url; do
  channel_url="${channel_url%/}"
  [[ "$channel_url" == "file://$CHANNEL" ]] || {
    echo "error: $name came from outside stage channel: $channel_url" >&2
    exit 1
  }
done < <(jq -r '.actions.LINK[] | [.name, (.channel // .url // "")] | @tsv' "$tmp/result.json")
echo "stage-only tool interface solve: OK ($(jq '.actions.LINK | length' "$tmp/result.json") packages)"
((CLOSURE_ONLY == 0)) || exit 0

# Solver closure alone does not prove the installed compiler/runtime policy.
CONDA_PKGS_DIRS="$tmp/pkgs" mamba create --yes --prefix "$tmp/prefix" \
  --offline --override-channels --channel "file://$CHANNEL" \
  --strict-channel-priority --platform linux-64 \
  sysroot_linux-64 clang llvm-libgcc libcxx make perl pkgconf openssl \
  ca-certificates ninja cmake gnuconfig gettext gettext-tools krb5 libssh2 libnghttp2 curl libcurl expat libexpat lzo lz4-c libarchive jsoncpp cppdap bzip2 libuv rhash c-ares keyutils libev libedit zlib libzlib zstd ncurses libiconv liblzma icu libpsl libxml2 libxml2-16 libxcrypt
bash "$ROOT/scripts/check-clang-policy.sh" "$tmp/prefix"
bash "$ROOT/scripts/check-clang-channel.sh" "$tmp/prefix"
python3 "$ROOT/scripts/check-glibc-baseline.py" "$tmp/prefix"
layout_args=()
[[ "${CHANNEL##*/}" != dirty ]] || layout_args+=(--allow-seed-runtime-aliases)
python3 "$ROOT/scripts/check-development-layout.py" "$tmp/prefix" "${layout_args[@]}"
for executable in cmake ninja make perl pkgconf openssl; do
  case "$executable" in
    openssl) "$tmp/prefix/bin/openssl" version ;;
    perl) "$tmp/prefix/bin/perl" -MStorable -e 'print "perl runtime: OK\n"' ;;
    *) "$tmp/prefix/bin/$executable" --version ;;
  esac
done
