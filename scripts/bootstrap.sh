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

MODE="${1:-all}"
if (($# > 1)) || [[ ! "$MODE" =~ ^(all|dirty|result|selfhost|test)$ ]]; then
  echo 'usage: bootstrap.sh [all|dirty|result|selfhost|test]' >&2
  exit 2
fi
export PLAN_FILE="${PLAN_FILE:-$ROOT/.build-output/affected-plan.json}"
if [[ "$MODE" == all ]]; then
  # Standalone local bootstrap has no diff or ordinary-package plan.
  export PLAN_FILE="$ROOT/.build-output/bootstrap-plan.json"
  mkdir -p "${PLAN_FILE%/*}"
  jq --arg head "$(git -C "$ROOT" rev-parse HEAD)" '{
    schema: "devkit-standalone-bootstrap-plan-v1", head_sha: $head,
    base_sha: $head, valid: true, bootstrap_required: true,
    ordinary_recipes: [], selected: [.[] | {recipe: ("recipes/" + .), bootstrap: true}]
  }' "$BOOTSTRAP_ORDER" >"$PLAN_FILE"
  for stage in dirty result selfhost test; do
    bash "$ROOT/scripts/bootstrap.sh" "$stage"
  done
  python3 "$ROOT/scripts/channel-artifact.py" merge --plan "$PLAN_FILE" \
    --channel "$ROOT/channels/result" --input selfhost "$ROOT/channels/result-rebuild"
  echo "bootstrap complete: $ROOT/channels/result"
  exit 0
fi
python3 "$ROOT/scripts/channel-artifact.py" validate-plan --plan "$PLAN_FILE"
[[ "$(jq -r '.bootstrap_required' "$PLAN_FILE")" == true ]] || {
  echo 'error: plan does not request bootstrap' >&2
  exit 1
}

clean_build_output() {
  local output_dir="$1"
  [[ -d "$output_dir" ]] || return 0
  python3 "$ROOT/scripts/clean-build-outputs.py" "$output_dir"
}

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
    [[ -x "$tool" ]] || {
      printf 'error: executable not found: %s\n' "$tool" >&2
      exit 1
    }
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
  compgen -G "$BUILD_ROOT/$output/linux-64/*.conda" >/dev/null &&
    cp "$BUILD_ROOT/$output"/linux-64/*.conda "$ROOT/channels/$channel/linux-64/"
  compgen -G "$BUILD_ROOT/$output/noarch/*.conda" >/dev/null &&
    cp "$BUILD_ROOT/$output"/noarch/*.conda "$ROOT/channels/$channel/noarch/"
  rattler-index fs "$ROOT/channels/$channel" --target-platform linux-64 >/dev/null
  rattler-index fs "$ROOT/channels/$channel" --target-platform noarch >/dev/null
}

recipe_variant() {
  local recipe="$1" stage_variant="$2"
  case "$recipe" in
    sysroot | llvm-libgcc | libcxx | clang | make | libxcrypt | perl | pkgconf | openssl | ninja | cmake | libuv | rhash | c-ares | keyutils | libev | libedit | bzip2 | zlib | zstd | ncurses | libiconv | liblzma | icu | gettext | krb5 | libssh2 | libnghttp2 | curl | expat | lzo | lz4-c | libarchive | jsoncpp | cppdap | libpsl | libxml2)
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
  local manifest="$ROOT/channels/$channel/stage-packages.txt"
  mkdir -p "${manifest%/*}"
  : >"$manifest"

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
        printf '%s/%s\n' "$subdir" "${archive##*/}" >>"$manifest"
      done
    done
  done
  if [[ "$channel" == result-rebuild ]]; then
    bash "$ROOT/scripts/check-result.sh" --closure-only "$ROOT/channels/$channel"
  else
    bash "$ROOT/scripts/check-result.sh" "$ROOT/channels/$channel"
  fi
}

prepare_output() {
  local channel="$1" input="$2"
  # Validate the input before clearing this stage's output. Never clear siblings.
  local -a archives
  mapfile -t archives < <(compgen -G "$ROOT/channels/$input/noarch/tzdata-*.conda" || true)
  ((${#archives[@]} == 1)) || {
    echo 'error: input channel must contain exactly one tzdata archive' >&2
    exit 1
  }
  rm -rf -- "$ROOT/channels/$channel"
  mkdir -p "$ROOT/channels/$channel/linux-64" "$ROOT/channels/$channel/noarch" "$BUILD_ROOT"
  cp "${archives[0]}" "$ROOT/channels/$channel/noarch/"
  rattler-index fs "$ROOT/channels/$channel" --target-platform linux-64 >/dev/null
  rattler-index fs "$ROOT/channels/$channel" --target-platform noarch >/dev/null
}

verify_input() {
  python3 "$ROOT/scripts/channel-artifact.py" verify --plan "$PLAN_FILE" \
    --stage "$1" --channel "$ROOT/channels/$2"
}

seal_output() {
  local stage="$1" channel="$2"
  shift 2
  python3 "$ROOT/scripts/channel-artifact.py" seal --plan "$PLAN_FILE" \
    --stage "$stage" --channel "$ROOT/channels/$channel" "$@"
}

read_bootstrap_order
case "$MODE" in
  dirty)
    "$ROOT/scripts/fetch-seed.sh"
    "$ROOT/scripts/check-seed.sh"
    prepare_output dirty seed
    # Dirty still prefers its own published packages, falling back to seed.
    run_stage dirty dirty seed
    seal_output dirty dirty
    ;;
  result)
    verify_input dirty dirty
    prepare_output result dirty
    run_stage result result dirty
    seal_output result result --input dirty "$ROOT/channels/dirty"
    ;;
  selfhost)
    verify_input result result
    prepare_output result-rebuild result
    # Input result is immutable; upstream tests run during this build only.
    run_stage result result-rebuild result
    seal_output selfhost result-rebuild --input result "$ROOT/channels/result"
    ;;
  test)
    verify_input selfhost result-rebuild
    bash "$ROOT/scripts/test-bootstrap-stage.sh" "$ROOT/channels/result-rebuild" \
      "$ROOT/channels/result-rebuild/stage-packages.txt"
    bash "$ROOT/scripts/check-result.sh" "$ROOT/channels/result-rebuild"
    # Tests must not mutate the channel handed off to ordinary builds.
    verify_input selfhost result-rebuild
    ;;
esac
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  printf 'Bootstrap stage %s completed.\n' "$MODE" >>"$GITHUB_STEP_SUMMARY"
fi
