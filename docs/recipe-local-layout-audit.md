# Recipe-local development layout migration

Work starts from `1b85f68978d6` on the isolated branch
`experiment/recipe-local-development-layout`. The existing PR branch is the
rollback reference; this experiment does not change the seed manifest.

## Scope and policy

Review all 54 recipes. Keep useful upstream install options and preserve
upstream-generated dependency metadata. Replace layout-only source patches and
shared development staging calls with explicit moves/path repairs owned by each
recipe. Keep unrelated functionality, RUNPATH choices and approved feature
scope. Do not extract shared move/rewrite helpers during this work.

Keep runtime SONAME libraries and plugins public. Hide development headers,
archives, unversioned linker interfaces and CMake/pkg-config metadata under
`lib/devkit`. Preserve relative symlinks, exported executable locations and
relocation. Compiler resources and language-internal headers/configuration are
not ordinary C/C++ development interfaces.

## Progress

Migration and validation are in progress. Record each recipe's treatment and
actual verification here before reporting the migration complete. Existing
successful CI artifacts may provide dependencies for local builds; they do not
constitute a new bootstrap of the revised recipes.
