#!/usr/bin/env bash
set -euo pipefail

# Produce the single revision-checked plan consumed by local and CI stages.

ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DEVKIT_CHANNEL="${DEVKIT_CHANNEL:-https://prefix.dev/black-desk}"
PLAN_FILE="${PLAN_FILE:-$ROOT/.build-output/affected-plan.json}"
HEAD_SHA="$(git -C "$ROOT" rev-parse HEAD)"

append_summary() {
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    printf '%s\n' "$1" >>"$GITHUB_STEP_SUMMARY"
  fi
}

if (($# != 1)); then
  printf 'usage: %s BASE_SHA\n' "$0" >&2
  exit 2
fi

BASE_SHA="$1"

git -C "$ROOT" cat-file -e "$BASE_SHA^{commit}" || {
  printf 'error: base commit not found: %s\n' "$BASE_SHA" >&2
  exit 1
}

for tool in git jq curl rattler-build rattler-index; do
  command -v "$tool" >/dev/null 2>&1 || {
    printf 'error: required tool not found: %s\n' "$tool" >&2
    exit 1
  }
done

verify_standalone_target_channel() {
  local subdir relation

  for subdir in linux-64 noarch; do
    relation="$(
      curl -fsSL "$DEVKIT_CHANNEL/$subdir/repodata.json" |
        jq -r '.info.channel_relations // {} | (.base // "") + "|" + (.overrides // "")'
    )"
    [[ "$relation" == "|" ]] || {
      printf 'error: %s/%s declares a CEP 42 channel relation: %s\n' \
        "$DEVKIT_CHANNEL" "$subdir" "$relation" >&2
      printf 'Clear the base and override channel relations in the prefix.dev settings.\n' >&2
      return 1
    }
  done
}

mkdir -p "$(dirname "$PLAN_FILE")"
# The same offline planner is used by developers and CI. Validate revisions
# before downloading dependencies or running the expensive bootstrap.
bash "$ROOT/scripts/dependency-graph/graph" plan --root "$ROOT" \
  --check --json "$BASE_SHA" >"$PLAN_FILE"

jq --arg head "$HEAD_SHA" --arg base "$BASE_SHA" '
  . + {
    head_sha: $head,
    base_sha: $base,
    bootstrap_required: any(.selected[]; .bootstrap),
    ordinary_recipes: ([.selected[] | select(.bootstrap == false) |
      .recipe | sub("^recipes/"; "")] | reduce .[] as $recipe
      ([]; if index($recipe) == null then . + [$recipe] else . end))
  }
' "$PLAN_FILE" >"$PLAN_FILE.tmp"
mv "$PLAN_FILE.tmp" "$PLAN_FILE"
python3 "$ROOT/scripts/channel-artifact.py" validate-plan --plan "$PLAN_FILE"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    printf 'bootstrap_required=%s\n' "$(jq -r '.bootstrap_required' "$PLAN_FILE")"
    printf 'ordinary_required=%s\n' "$(jq -r '.ordinary_recipes | length > 0' "$PLAN_FILE")"
    printf 'build_required=%s\n' "$(jq -r '.selected | length > 0' "$PLAN_FILE")"
  } >>"$GITHUB_OUTPUT"
fi
if [[ "$(jq '.selected | length' "$PLAN_FILE")" == 0 ]]; then
  append_summary 'No recipe changes; package build skipped.'
  exit 0
fi
verify_standalone_target_channel

FULL_REBUILD="$(jq '.global_change | if . then 1 else 0 end' "$PLAN_FILE")"
mapfile -t CHANGED_RECIPES < <(jq -r '.changed_recipes[]' "$PLAN_FILE")

printf 'Affected package plan:\n'
jq . "$PLAN_FILE"

append_summary '## Affected package builds'
append_summary ''
append_summary "- Base: \`${BASE_SHA}\`"
append_summary "- Head: \`${HEAD_SHA}\`"
append_summary '- Target channel relations: none'
append_summary "- Global bootstrap input change: $(
  if ((FULL_REBUILD)); then
    printf 'yes'
  else
    printf 'no'
  fi
)"
append_summary ''
append_summary '### Changed recipe roots'
append_summary ''

for recipe in "${CHANGED_RECIPES[@]}"; do
  append_summary "- \`${recipe}\`"
done

append_summary ''
append_summary '### Rebuild plan'
append_summary ''
append_summary '| Package | Recipe | Layer | Reason |'
append_summary '| ------- | ------ | ----- | ------ |'

while IFS=$'\t' read -r package recipe bootstrap reasons; do
  layer=ordinary
  ((bootstrap == 1)) && layer=bootstrap
  append_summary "| \`${package}\` | \`${recipe#recipes/}\` | ${layer} | ${reasons} |"
done < <(
  jq -r '.selected[] | [
    .package,
    .recipe,
    (.bootstrap | if . then 1 else 0 end),
    (.reasons | join("; "))
  ] | @tsv' "$PLAN_FILE"
)

append_summary ''
