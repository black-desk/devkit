#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DEVKIT_CHANNEL="${DEVKIT_CHANNEL:-https://prefix.dev/black-desk}"
PLAN_FILE="${PLAN_FILE:-$ROOT/.build-output/affected-plan.json}"
python3 "$ROOT/scripts/channel-artifact.py" validate-plan --plan "$PLAN_FILE"
if [[ "$(jq '.ordinary_recipes | length' "$PLAN_FILE")" == 0 ]]; then
  echo 'No ordinary recipes selected.'
  exit 0
fi
BOOTSTRAP_REQUIRED="$(jq -r '.bootstrap_required' "$PLAN_FILE")"
if [[ "$BOOTSTRAP_REQUIRED" == true ]]; then
  python3 "$ROOT/scripts/channel-artifact.py" verify --plan "$PLAN_FILE" \
    --channel "$ROOT/channels/result-rebuild" --stage selfhost
fi
rm -rf -- "$ROOT/channels/ordinary"
mkdir -p "$ROOT/channels/ordinary/linux-64" "$ROOT/channels/ordinary/noarch"
: >"$ROOT/channels/ordinary/stage-packages.txt"
publish_recipe() {
  local recipe="$1"
  local output_dir="$ROOT/output/$recipe"
  local archive subdir archive_count=0

  mkdir -p "$ROOT/channels/ordinary/linux-64" "$ROOT/channels/ordinary/noarch"

  for subdir in linux-64 noarch; do
    [[ -d "$output_dir/$subdir" ]] || continue
    while IFS= read -r -d '' archive; do
      cp "$archive" "$ROOT/channels/ordinary/$subdir/"
      printf '%s/%s\n' "$subdir" "${archive##*/}" >>"$ROOT/channels/ordinary/stage-packages.txt"
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

  rattler-index fs "$ROOT/channels/ordinary" --target-platform linux-64 >/dev/null
  rattler-index fs "$ROOT/channels/ordinary" --target-platform noarch >/dev/null
}

clean_recipe_output() {
  local output_dir="$ROOT/output/$1"

  [[ -d "$output_dir" ]] || return 0

  # Keep each recipe's source cache at its existing stable path. Package
  # archives, logs, and temporary build directories are recreated for this PR.
  python3 "$ROOT/scripts/clean-build-outputs.py" "$output_dir"
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
    sysroot | llvm-libgcc | libcxx | clang | make | perl | pkgconf | openssl | ninja | cmake | zlib | zstd | ncurses | libiconv | liblzma | icu | libxml2)
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

  mapfile -t recipes < <(jq -r '.ordinary_recipes[]' "$PLAN_FILE")

  if ((${#recipes[@]} == 0)); then
    return 0
  fi

  mkdir -p "$ROOT/channels/ordinary/linux-64" "$ROOT/channels/ordinary/noarch"
  rattler-index fs "$ROOT/channels/ordinary" --target-platform linux-64 >/dev/null
  rattler-index fs "$ROOT/channels/ordinary" --target-platform noarch >/dev/null

  for recipe in "${recipes[@]}"; do
    if [[ "$BOOTSTRAP_REQUIRED" == true ]]; then
      build_recipe "$recipe" "$ROOT/channels/ordinary" \
        "$ROOT/channels/result-rebuild" "$DEVKIT_CHANNEL"
    else
      build_recipe "$recipe" "$ROOT/channels/ordinary" "$DEVKIT_CHANNEL"
    fi
  done
}

build_selected_ordinary_recipes
input_args=()
if [[ "$BOOTSTRAP_REQUIRED" == true ]]; then
  input_args=(--input selfhost "$ROOT/channels/result-rebuild")
fi
python3 "$ROOT/scripts/channel-artifact.py" seal --plan "$PLAN_FILE" \
  --channel "$ROOT/channels/ordinary" --stage ordinary "${input_args[@]}"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  printf 'Ordinary recipes built: %s\n' "$(jq -r '.ordinary_recipes | join(", ")' "$PLAN_FILE")" >>"$GITHUB_STEP_SUMMARY"
fi
