#!/usr/bin/env bash
set -euo pipefail
# Local convenience entry point; CI runs these same steps in separate jobs.
ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export PLAN_FILE="${PLAN_FILE:-$ROOT/.build-output/affected-plan.json}"
bash "$ROOT/scripts/affected-plan.sh" "$@"
inputs=()
if [[ "$(jq -r '.bootstrap_required' "$PLAN_FILE")" == true ]]; then
  bash "$ROOT/scripts/bootstrap.sh" dirty
  bash "$ROOT/scripts/bootstrap.sh" result
  bash "$ROOT/scripts/bootstrap.sh" selfhost
  bash "$ROOT/scripts/bootstrap.sh" test
  inputs+=(--input selfhost "$ROOT/channels/result-rebuild")
fi
if [[ "$(jq '.ordinary_recipes | length' "$PLAN_FILE")" != 0 ]]; then
  bash "$ROOT/scripts/build-ordinary.sh"
  inputs+=(--input ordinary "$ROOT/channels/ordinary")
fi
if ((${#inputs[@]})); then
  python3 "$ROOT/scripts/channel-artifact.py" merge --plan "$PLAN_FILE" \
    --channel "$ROOT/channels/result" "${inputs[@]}"
else
  rm -rf -- "$ROOT/channels/result"
  mkdir -p "$ROOT/channels/result"
fi
