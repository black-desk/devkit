#!/usr/bin/env bash
set -euo pipefail

# Run the complete bootstrap:
#   seed -> dirty toolchain -> result toolchain -> result self-host rebuild
#
# The script deliberately publishes each stage into its channel before the
# next stage resolves dependencies.  This keeps the dependency graph the same
# as a clean invocation of rattler-build rather than relying on stale output
# directories as implicit channels.

ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="$ROOT/output"
BOOTSTRAP_ORDER="$ROOT/bootstrap-order.json"

clean_build_outputs() {
  [[ -d "$BUILD_ROOT" ]] || return 0

  # Rattler-Build puts source caches below the output directory. Preserve
  # every src_cache directory, but remove package archives, logs, and build
  # directories outside those caches.
  find "$BUILD_ROOT" -mindepth 1 -type d -name src_cache -prune -o \
    ! -type d -exec rm -f -- {} +
  find "$BUILD_ROOT" -mindepth 1 -depth -type d -name src_cache -prune -o \
    -type d -empty -delete
}

clean_build_output() {
  local output_dir="$1"
  [[ -d "$output_dir" ]] || return 0

  # Keep the source cache at a stable per-recipe path so each stage can reuse
  # downloaded sources while still compiling from a fresh build directory.
  find "$output_dir" -mindepth 1 -type d -name src_cache -prune -o \
    ! -type d -exec rm -f -- {} +
  find "$output_dir" -mindepth 1 -depth -type d -name src_cache -prune -o \
    -type d -empty -delete
}

reset_generated_state() {
  # Seed archives are downloads and remain in place; fetch-seed.sh re-verifies
  # and re-indexes them. Compiled dirty/result outputs are rebuilt cleanly.
  rm -rf -- "$ROOT/channels/dirty" "$ROOT/channels/result"
  mkdir -p "$ROOT/channels/seed" "$ROOT/channels/dirty" \
    "$ROOT/channels/result" "$BUILD_ROOT"
  clean_build_outputs
  touch "$ROOT/channels/seed/.gitkeep" "$ROOT/channels/dirty/.gitkeep" \
    "$ROOT/channels/result/.gitkeep"
}

reset_generated_state

if [[ -n "${RATTLER_BUILD:-}" ]]; then
  RBT="$RATTLER_BUILD"
elif command -v rattler-build >/dev/null 2>&1; then
  RBT="$(command -v rattler-build)"
else
  printf 'error: rattler-build not found in PATH; set RATTLER_BUILD to its absolute path\n' >&2
  exit 1
fi

for tool in "$RBT" rattler-index mamba jq; do
  if [[ "$tool" == */* ]]; then
    [[ -x "$tool" ]] || { printf 'error: executable not found: %s\n' "$tool" >&2; exit 1; }
  elif ! command -v "$tool" >/dev/null 2>&1; then
    printf 'error: required tool not found: %s\n' "$tool" >&2
    exit 1
  fi
done

declare -a BOOTSTRAP_RECIPES
read_bootstrap_order() {
  jq -e '
    type == "array" and
    length > 0 and
    all(.[]; type == "string" and length > 0) and
    length == (unique | length)
  ' "$BOOTSTRAP_ORDER" >/dev/null || {
    printf 'error: %s must be a non-empty array of unique recipe names\n' \
      "$BOOTSTRAP_ORDER" >&2
    exit 1
  }

  mapfile -t BOOTSTRAP_RECIPES < <(jq -r '.[]' "$BOOTSTRAP_ORDER")
  local recipe
  for recipe in "${BOOTSTRAP_RECIPES[@]}"; do
    [[ "$recipe" != */* && -f "$ROOT/recipes/$recipe/recipe.yaml" ]] || {
      printf 'error: bootstrap recipe not found: %s\n' "$recipe" >&2
      exit 1
    }
  done
}

build() {
  local recipe="$1" variant="$2" output="$3"
  shift 3
  local -a variant_args=()
  [[ -z "$variant" ]] || variant_args=(--variant-config "$ROOT/variants/$variant.yaml")
  clean_build_output "$BUILD_ROOT/$output"
  "$RBT" build \
    --recipe "$ROOT/recipes/$recipe/recipe.yaml" \
    --target-platform linux-64 \
    --channel-priority strict \
    "${variant_args[@]}" \
    --output-dir "$BUILD_ROOT/$output" \
    "$@"
}

publish() {
  local output="$1" channel="$2"
  mkdir -p "$ROOT/channels/$channel/linux-64" "$ROOT/channels/$channel/noarch"
  compgen -G "$BUILD_ROOT/$output/linux-64/*.conda" >/dev/null && \
    cp "$BUILD_ROOT/$output"/linux-64/*.conda "$ROOT/channels/$channel/linux-64/"
  compgen -G "$BUILD_ROOT/$output/noarch/*.conda" >/dev/null && \
    cp "$BUILD_ROOT/$output"/noarch/*.conda "$ROOT/channels/$channel/noarch/"
  rattler-index fs "$ROOT/channels/$channel" --target-platform linux-64 >/dev/null
  rattler-index fs "$ROOT/channels/$channel" --target-platform noarch >/dev/null
}

recipe_variant() {
  local recipe="$1" stage_variant="$2"
  case "$recipe" in
    sysroot|gcc-toolchain|binutils|make)
      printf '%s\n' "$stage_variant"
      ;;
    *)
      printf '\n'
      ;;
  esac
}

run_stage() {
  local stage_variant="$1" channel="$2"
  shift 2

  local recipe variant output
  for recipe in "${BOOTSTRAP_RECIPES[@]}"; do
    variant="$(recipe_variant "$recipe" "$stage_variant")"
    output="$recipe"
    build "$recipe" "$variant" "$output" "$@"
    publish "$output" "$channel"
  done
}

publish_seed_tzdata() {
  local -a archives
  mapfile -t archives < <(compgen -G "$ROOT/channels/seed/noarch/tzdata-*.conda" || true)
  ((${#archives[@]} == 1)) || {
    printf 'error: seed channel does not contain tzdata\n' >&2
    exit 1
  }
  mkdir -p "$ROOT/channels/dirty/noarch" "$ROOT/channels/result/noarch"
  cp "${archives[0]}" "$ROOT/channels/dirty/noarch/"
  cp "${archives[0]}" "$ROOT/channels/result/noarch/"
  rattler-index fs "$ROOT/channels/dirty" --target-platform noarch >/dev/null
  rattler-index fs "$ROOT/channels/result" --target-platform noarch >/dev/null
}

read_bootstrap_order

"$ROOT/scripts/fetch-seed.sh"
"$ROOT/scripts/check-seed.sh"
publish_seed_tzdata

# Dirty stage: build the local sysroot first, then use the seed compiler
# interfaces with that sysroot to produce the first local toolchain stage.
run_stage dirty dirty \
  --channel "$ROOT/channels/dirty" \
  --channel "$ROOT/channels/seed"

# Result stage: rebuild the same order against the result sysroot and dirty
# compiler interfaces.  The seed channel is deliberately not available here:
# result must not silently fall back to seed packages.
run_stage result result \
  --channel "$ROOT/channels/result" \
  --channel "$ROOT/channels/dirty"

"$ROOT/scripts/check-result.sh"

# Self-host stage: rebuild every result package using result as the bootstrap
# channel.  Each package is published back into result immediately so later
# packages consume the newly rebuilt interfaces.  No dirty or seed channel is
# visible in this stage.
run_stage result result \
  --channel "$ROOT/channels/result"

"$ROOT/scripts/check-result.sh"
printf 'bootstrap complete: %s\n' "$ROOT/channels/result"
