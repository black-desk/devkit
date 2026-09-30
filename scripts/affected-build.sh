#!/usr/bin/env bash
set -euo pipefail

# Build packages affected by a pull request. Recipe changes are expanded
# through the rendered dependency graph; changes to global bootstrap inputs
# conservatively select every current recipe.

ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DEVKIT_CHANNEL="${DEVKIT_CHANNEL:-https://prefix.dev/black-desk}"
CONDA_FORGE_CHANNEL="https://prefix.dev/conda-forge"
PLAN_FILE="${PLAN_FILE:-$ROOT/.build-output/affected-plan.json}"
CHANGED_FILES_FILE="$(mktemp)"
CHANGED_RECIPES_FILE="$(mktemp)"
HEAD_SHA="$(git -C "$ROOT" rev-parse HEAD)"
trap 'rm -f "$CHANGED_FILES_FILE" "$CHANGED_RECIPES_FILE"' EXIT

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

for tool in git jq rattler-build rattler-index; do
  command -v "$tool" >/dev/null 2>&1 || {
    printf 'error: required tool not found: %s\n' "$tool" >&2
    exit 1
  }
done

FULL_REBUILD=0
git -C "$ROOT" diff --no-renames --name-only --diff-filter=ACDMRT \
  "$BASE_SHA"...HEAD >"$CHANGED_FILES_FILE"

while IFS= read -r path; do
  case "$path" in
    bootstrap-order.json | variants/* | seed-packages.tsv | \
    scripts/bootstrap.sh | scripts/fetch-seed.sh | scripts/check-seed.sh | scripts/check-result.sh)
      FULL_REBUILD=1
      ;;
    recipes/*/recipe.yaml | recipes/*/*)
      recipe="${path#recipes/}"
      printf '%s\n' "${recipe%%/*}" >>"$CHANGED_RECIPES_FILE"
      ;;
    recipes/*)
      printf 'error: unexpected file directly below recipes/: %s\n' "$path" >&2
      exit 1
      ;;
  esac
done <"$CHANGED_FILES_FILE"

sort -u -o "$CHANGED_RECIPES_FILE" "$CHANGED_RECIPES_FILE"

# Validate changed recipe names before a global-input fallback can replace the
# roots with the complete current recipe set.
while IFS= read -r recipe; do
  [[ "$recipe" != */* && -f "$ROOT/recipes/$recipe/recipe.yaml" ]] || {
    printf 'error: changed recipe missing from head tree: %s\n' "$recipe" >&2
    printf 'Recipe deletion is not handled by affected CI yet.\n' >&2
    exit 1
  }
done <"$CHANGED_RECIPES_FILE"

if ((FULL_REBUILD)); then
  : >"$CHANGED_RECIPES_FILE"
  for recipe_file in "$ROOT"/recipes/*/recipe.yaml; do
    [[ -f "$recipe_file" ]] || continue
    basename "$(dirname "$recipe_file")" >>"$CHANGED_RECIPES_FILE"
  done
fi

if [[ ! -s "$CHANGED_RECIPES_FILE" ]]; then
  printf 'No recipe changes; package build skipped.\n'
  append_summary '## Affected package builds'
  append_summary ''
  append_summary "No recipe changes between \`${BASE_SHA}\` and \`${HEAD_SHA}\`; package build skipped."
  exit 0
fi

mapfile -t CHANGED_RECIPES <"$CHANGED_RECIPES_FILE"
BUILT_ORDINARY_RECIPES=()

mkdir -p "$(dirname "$PLAN_FILE")"

BOOTSTRAP_RECIPE_CHANGED=0
for recipe in "${CHANGED_RECIPES[@]}"; do
  if [[ "$(
    jq --arg recipe "$recipe" 'index($recipe) != null' \
      "$ROOT/bootstrap-order.json"
  )" == true ]]; then
    BOOTSTRAP_RECIPE_CHANGED=1
    break
  fi
done

if ((BOOTSTRAP_RECIPE_CHANGED)); then
  # The published channel can be empty while it is being initialized. Render
  # the graph only after the local bootstrap generation is available.
  bash "$ROOT/scripts/bootstrap.sh"
  bash "$ROOT/scripts/dependency-graph/graph" affected \
    --root "$ROOT" \
    --channel "$ROOT/channels/result" \
    --channel "$DEVKIT_CHANNEL" \
    --channel "$CONDA_FORGE_CHANNEL" \
    --json "${CHANGED_RECIPES[@]}" >"$PLAN_FILE"
else
  bash "$ROOT/scripts/dependency-graph/graph" affected \
    --root "$ROOT" \
    --channel "$DEVKIT_CHANNEL" \
    --channel "$CONDA_FORGE_CHANNEL" \
    --json "${CHANGED_RECIPES[@]}" >"$PLAN_FILE"
fi

BOOTSTRAP_COUNT="$(
  jq '[.selected[] | select(.bootstrap == true)] | length' "$PLAN_FILE"
)"

printf 'Affected package plan:\n'
jq . "$PLAN_FILE"

append_summary '## Affected package builds'
append_summary ''
append_summary "- Base: \`${BASE_SHA}\`"
append_summary "- Head: \`${HEAD_SHA}\`"
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

publish_recipe() {
  local recipe="$1"
  local output_dir="$ROOT/output/$recipe"
  local archive subdir archive_count=0

  mkdir -p "$ROOT/channels/result/linux-64" "$ROOT/channels/result/noarch"

  for subdir in linux-64 noarch; do
    [[ -d "$output_dir/$subdir" ]] || continue
    while IFS= read -r -d '' archive; do
      cp "$archive" "$ROOT/channels/result/$subdir/"
      archive_count=$((archive_count + 1))
    done < <(
      find "$output_dir/$subdir" -maxdepth 1 -type f \
        \( -name '*.conda' -o -name '*.tar.bz2' \) -print0
    )
  done

  ((archive_count > 0)) || {
    printf 'error: no package archive found for recipes/%s\n' "$recipe" >&2
    return 1
  }

  rattler-index fs "$ROOT/channels/result" --target-platform linux-64 >/dev/null
  rattler-index fs "$ROOT/channels/result" --target-platform noarch >/dev/null
}

clean_recipe_output() {
  local output_dir="$ROOT/output/$1"

  [[ -d "$output_dir" ]] || return 0

  # Keep each recipe's source cache at its existing stable path. Package
  # archives, logs, and temporary build directories are recreated for this PR.
  find "$output_dir" -mindepth 1 -type d -name src_cache -prune -o \
    ! -type d -exec rm -f -- {} +
  find "$output_dir" -mindepth 1 -depth -type d -name src_cache -prune -o \
    -type d -empty -delete
}

build_recipe() {
  local recipe="$1"
  shift
  local -a channels=() variant_args=()
  local channel

  for channel in "$@"; do
    channels+=(--channel "$channel")
  done

  case "$recipe" in
    sysroot | gcc-toolchain | binutils | make)
      variant_args=(--variant-config "$ROOT/variants/result.yaml")
      ;;
  esac

  clean_recipe_output "$recipe"
  printf 'Building recipes/%s\n' "$recipe"
  rattler-build build \
    --recipe "$ROOT/recipes/$recipe/recipe.yaml" \
    --target-platform linux-64 \
    --channel-priority strict \
    --no-config \
    "${variant_args[@]}" \
    --output-dir "$ROOT/output/$recipe" \
    "${channels[@]}"

  publish_recipe "$recipe"
}

build_selected_ordinary_recipes() {
  local -a recipes=()
  local recipe

  while IFS= read -r recipe; do
    [[ -n "$recipe" ]] && recipes+=("$recipe")
  done < <(
    jq -r '
      .selected[]
      | select(.bootstrap == false)
      | .recipe
      | sub("^recipes/"; "")
    ' "$PLAN_FILE" | awk '!seen[$0]++'
  )

  if ((${#recipes[@]} == 0)); then
    return 0
  fi

  mkdir -p "$ROOT/channels/result/linux-64" "$ROOT/channels/result/noarch"
  rattler-index fs "$ROOT/channels/result" --target-platform linux-64 >/dev/null
  rattler-index fs "$ROOT/channels/result" --target-platform noarch >/dev/null

  for recipe in "${recipes[@]}"; do
    build_recipe "$recipe" \
      "$ROOT/channels/result" "$DEVKIT_CHANNEL" "$CONDA_FORGE_CHANNEL"
    BUILT_ORDINARY_RECIPES+=("$recipe")
  done
}

if ((BOOTSTRAP_COUNT > 0)); then
  # Bootstrap recipes form a cyclic generation and therefore use the complete
  # seed -> dirty -> result -> self-host fixed point rather than a package-wise
  # channel build.  Selected ordinary consumers are rebuilt against that result.
  ((BOOTSTRAP_RECIPE_CHANGED)) || bash "$ROOT/scripts/bootstrap.sh"
  build_selected_ordinary_recipes
else
  mkdir -p "$ROOT/channels/result"
  # Start with an empty local result overlay. Each built package is published
  # into it before the next selected package is solved.
  find "$ROOT/channels/result" -mindepth 1 -maxdepth 1 \
    ! -name .gitkeep -exec rm -rf -- {} +
  build_selected_ordinary_recipes
fi

append_summary ''
append_summary '### Result'
append_summary ''

if ((BOOTSTRAP_COUNT > 0)); then
  append_summary 'The complete bootstrap generation was rebuilt through the fixed point.'
else
  append_summary 'No bootstrap recipe was rebuilt.'
fi

if ((${#BUILT_ORDINARY_RECIPES[@]} == 0)); then
  append_summary 'No ordinary recipes were rebuilt.'
else
  append_summary "Ordinary recipes rebuilt: ${BUILT_ORDINARY_RECIPES[*]}"
fi

append_summary ''
append_summary '#### Produced archives'
append_summary ''
append_summary '| Archive | Platform |'
append_summary '| ------- | -------- |'

for subdir in linux-64 noarch; do
  [[ -d "$ROOT/channels/result/$subdir" ]] || continue
  while IFS= read -r -d '' archive; do
    append_summary "| \`${archive##*/}\` | \`${subdir}\` |"
  done < <(
    find "$ROOT/channels/result/$subdir" -maxdepth 1 -type f \
      \( -name '*.conda' -o -name '*.tar.bz2' \) -print0 | sort -z
  )
done

printf 'Affected package builds completed.\n'
