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
  python3 "$ROOT/scripts/clean-build-outputs.py" "$BUILD_ROOT"
}

clean_build_output() {
  local output_dir="$1"
  [[ -d "$output_dir" ]] || return 0

  # Keep the source cache at a stable per-recipe path so each stage can reuse
  # downloaded sources while still compiling from a fresh build directory.
  python3 "$ROOT/scripts/clean-build-outputs.py" "$output_dir"
}

reset_generated_state() {
  # Seed archives are downloads and remain in place; fetch-seed.sh re-verifies
  # and re-indexes them. Compiled dirty/result outputs are rebuilt cleanly.
  rm -rf -- "$ROOT/channels/dirty" "$ROOT/channels/result" "$ROOT/channels/result-rebuild"
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
  if [[ "$recipe" == llvm-libgcc && "$variant" == dirty ]]; then
    mkdir -p "$BUILD_ROOT/bootstrap"
    python3 "$ROOT/scripts/seed-libgcc-variant.py" > "$BUILD_ROOT/bootstrap/seed-libgcc-variant.yaml"
    variant_args+=(--variant-config "$BUILD_ROOT/bootstrap/seed-libgcc-variant.yaml")
  fi
  local recipe_file="$ROOT/recipes/$recipe/recipe.yaml"
  clean_build_output "$BUILD_ROOT/$output"
  DEVKIT_RUN_TESTS="$RUN_UPSTREAM_TESTS" "$RBT" build \
    --recipe "$recipe_file" \
    --target-platform linux-64 \
    --no-config \
    --test skip \
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
    sysroot|llvm-libgcc|libcxx|clang|make|libxcrypt|perl|pkgconf|openssl|ninja|cmake|libuv|rhash|c-ares|keyutils|libev|libedit|bzip2|zlib|zstd|ncurses|libiconv|liblzma|icu|gettext|krb5|libssh2|libnghttp2|curl|expat|lzo|lz4-c|libarchive|jsoncpp|cppdap|libpsl|libxml2)
      printf '%s\n' "$stage_variant"
      ;;
    *)
      printf '\n'
      ;;
  esac
}

run_stage() {
  local stage_variant="$1" channel="$2" input_channel="$3"
  local RUN_UPSTREAM_TESTS=0
  [[ "$channel" != result-rebuild ]] || RUN_UPSTREAM_TESTS=1
  printf 'Bootstrap stage %s: upstream/package tests %s\n' \
    "$channel" "$RUN_UPSTREAM_TESTS"
  local manifest="$BUILD_ROOT/bootstrap/$channel-packages.txt"
  mkdir -p "${manifest%/*}"
  : > "$manifest"

  local recipe variant output
  for recipe in "${BOOTSTRAP_RECIPES[@]}"; do
    variant="$(recipe_variant "$recipe" "$stage_variant")"
    output="$recipe"
    if [[ "$stage_variant" == dirty ]]; then
      build "$recipe" "$variant" "$output" --channel "$ROOT/channels/dirty" --channel "$ROOT/channels/seed"
    else
      build "$recipe" "$variant" "$output" --channel "$ROOT/channels/$input_channel"
    fi
    publish "$output" "$channel"
    local subdir archive
    for subdir in linux-64 noarch; do
      for archive in "$BUILD_ROOT/$output/$subdir/"*.conda; do
        [[ -f "$archive" ]] || continue
        printf '%s/%s\n' "$subdir" "${archive##*/}" >> "$manifest"
      done
    done
  done
  if [[ "$channel" == result-rebuild ]]; then
    bash "$ROOT/scripts/test-bootstrap-stage.sh" "$ROOT/channels/$channel" "$manifest"
  fi
  bash "$ROOT/scripts/check-result.sh" "$ROOT/channels/$channel"
}

publish_seed_tzdata() {
  local -a archives
  mapfile -t archives < <(compgen -G "$ROOT/channels/seed/noarch/tzdata-*.conda" || true)
  ((${#archives[@]} == 1)) || {
    printf 'error: seed channel does not contain tzdata\n' >&2
    exit 1
  }
  local channel
  for channel in dirty result result-rebuild; do
    mkdir -p "$ROOT/channels/$channel/noarch"
    cp "${archives[0]}" "$ROOT/channels/$channel/noarch/"
    rattler-index fs "$ROOT/channels/$channel" --target-platform noarch >/dev/null
  done
}

read_bootstrap_order

"$ROOT/scripts/fetch-seed.sh"
"$ROOT/scripts/check-seed.sh"
publish_seed_tzdata

# Dirty stage: both environments prefer already published dirty packages,
# falling back to seed. Compatibility meta outputs bridge seed split names.
run_stage dirty dirty seed

# Result stage: rebuild the same order using dirty sysroot and compiler
# interfaces. The seed channel is deliberately not available here:
# result must not silently fall back to seed packages.
run_stage result result dirty

# Self-host stage: read only the completed result generation. New packages
# go into a separate channel so subsequent builds cannot consume them.
run_stage result result-rebuild result
# Keep the input generation immutable throughout self-hosting and its tests.
# Promote the rebuilt generation only after all stage checks pass.
rm -rf -- "$ROOT/channels/result"
mv "$ROOT/channels/result-rebuild" "$ROOT/channels/result"
printf 'bootstrap complete: %s\n' "$ROOT/channels/result"
