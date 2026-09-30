#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX_CHANNEL="${PREFIX_CHANNEL:-black-desk}"

append_summary() {
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    printf '%s\n' "$1" >>"$GITHUB_STEP_SUMMARY"
  fi
}

command -v rattler-build >/dev/null 2>&1 || {
  printf 'error: required tool not found: rattler-build\n' >&2
  exit 1
}

archives=()
for subdir in linux-64 noarch; do
  while IFS= read -r -d '' archive; do
    archives+=("$archive")
  done < <(
    find "$ROOT/channels/result/$subdir" -maxdepth 1 -type f \
      \( -name '*.conda' -o -name '*.tar.bz2' \) -print0 2>/dev/null
  )
done

if ((${#archives[@]} == 0)); then
  printf 'No package archives in channels/result; upload skipped.\n'
  exit 0
fi

printf 'Uploading %d package archive(s) to prefix.dev/%s:\n' \
  "${#archives[@]}" "$PREFIX_CHANNEL"
for archive in "${archives[@]}"; do
  printf '  - %s\n' "${archive#"$ROOT"/}"
done

append_summary '## Published packages'
append_summary ''
append_summary "- Channel: \`${PREFIX_CHANNEL}\`"
append_summary "- Uploaded archives: ${#archives[@]}"
append_summary ''
append_summary '| Archive | Platform |'
append_summary '| ------- | -------- |'

for archive in "${archives[@]}"; do
  case "$archive" in
    */linux-64/*) platform='linux-64' ;;
    */noarch/*) platform='noarch' ;;
    *) platform='unknown' ;;
  esac
  append_summary "| \`${archive##*/}\` | \`${platform}\` |"
done

rattler-build upload prefix \
  --channel "$PREFIX_CHANNEL" \
  "${archives[@]}"
