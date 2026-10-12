#!/usr/bin/env bash
# Source in recipes; direct builds run upstream tests unless explicitly skipped.
DEVKIT_RUN_TESTS="${DEVKIT_RUN_TESTS:-1}"
case "${DEVKIT_RUN_TESTS}" in
  0|1) ;;
  *)
    printf 'error: DEVKIT_RUN_TESTS must be 0 or 1\n' >&2
    return 1
    ;;
esac

devkit_test() {
  if [[ "${DEVKIT_RUN_TESTS}" == 1 ]]; then
    "$@"
  else
    printf 'Skipping upstream tests: %s\n' "$*"
  fi
}
