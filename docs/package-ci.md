# Package CI stages

Packages uses one revision-checked plan and five separately scheduled execution
jobs. The plan job has a 30-minute limit; dirty, result, selfhost, smoke and
ordinary each have a 360-minute limit. Existing PR builds remain unpublished;
main pushes publish only after every required build and test succeeds.

| Job      | Input                                                  | Work                                                                                         | Output                                |
| -------- | ------------------------------------------------------ | -------------------------------------------------------------------------------------------- | ------------------------------------- |
| plan     | Event base commit and checkout                         | Check revisions, calculate affected closure and recipe order, check target channel relations | build-plan                            |
| dirty    | Plan and seed-packages.tsv                             | Fetch/check seed; build with dirty preferred over seed; stage checks                         | dirty-channel                         |
| result   | Plan and dirty-channel                                 | Build using only complete dirty; stage checks                                                | result-channel                        |
| selfhost | Plan and result-channel                                | Build using only immutable result; full upstream suites; closure check                       | selfhost-channel                      |
| smoke    | Plan and selfhost-channel                              | Independent package tests, compiler/runtime policy and glibc baseline checks                 | Job success; input artifact unchanged |
| ordinary | Plan, optional tested selfhost-channel, public channel | Build selected ordinary recipes in dependency order; upstream/package tests                  | ordinary-channel                      |

Dirty and result skip upstream suites and independent package tests. Selfhost
retains all upstream workloads, including the full zstd fuzzer. Its packaged
recipe tests run in smoke after the complete selfhost channel is available.
Dirty/result retain existing channel closure/compiler/runtime checks. Selfhost
checks solver closure before handing off; smoke performs its full channel
checks.

A plan with no bootstrap selection skips dirty/result/selfhost/smoke. Ordinary
then resolves against its own output overlay and the public devkit channel. With
a bootstrap selection it instead prefers its ordinary overlay, then the tested
selfhost channel, then the public channel. Conda-forge is never a target
fallback. A plan with no ordinary selection skips ordinary. A plan with no
selected outputs skips all five execution jobs and publishing.

Ordinary and publication use explicit conditions that permit planned dependency
skips. Failure/cancellation of a required predecessor cannot enable a downstream
job. packages-pass checks each execution job against the plan: expected skips
are accepted, failure/cancellation or unexpected skips fail the gate.
Publication depends on packages-pass succeeding and uses plan only to read
build/artifact selection controls; it cannot start before the final gate passes.

## Portable handoffs

The small boolean controls bootstrap_required, bootstrap_build_required,
ordinary_required and build_required are GitHub job outputs. bootstrap_required
still means the plan needs a selfhost channel; bootstrap_build_required means
that channel must be compiled rather than restored from cache. The plan job also
exports bootstrap_cache_key. The complete affected-plan.json is an artifact
containing the selected outputs, dependency order, revision validation,
base/head commits and ordered deduplicated ordinary recipe list. Every consumer
reads this same file instead of recomputing the plan.

Each channel artifact is a tar.gz containing its channel directory, linux-64 and
noarch package archives and indexes, stage-packages.txt and stage-state.json.
The relative package manifest selects freshly built outputs for independent
package tests; seed tzdata is carried in the channel but is not an upstream test
output. Dirty alone downloads seed; subsequent jobs carry tzdata from their
input channel. Dirty's seed compatibility variant remains generated from the
verified seed metadata.

stage-state.json schema 2 records stage, original checkout commit, plan/seed
manifest SHA-256, bootstrap input SHA-256, input state SHA-256 and the relative
file names, sizes and hashes. Every consumer requires a plan for its current
checkout. Bootstrap channels are reusable across commits and plans only when
their bootstrap input hash matches; ordinary outputs remain bound to the exact
current commit and plan. Consumers reject missing, extra or changed files,
incorrect stage/seed/input hashes, and publication inputs from incompatible
stage attempts. Only successfully checked stages are sealed and uploaded. Tar
preserves channel files; installed environments, build trees and runner absolute
paths are not transferred. Artifacts belong to the current workflow run and are
retained for three days. Pixi's existing orchestration cache remains optional;
it is not a channel handoff.

selfhost-channel contains channels/result-rebuild. Ordinary consumes it
read-only and publishes only its own new packages into channels/ordinary.
Publishing verifies and merges those applicable artifacts into channels/result,
rejects colliding archive names, recreates indexes and invokes the existing OIDC
uploader. A bootstrap-only build publishes selfhost directly; an ordinary-only
build publishes only its new packages. No placeholder artifact is needed for a
skipped stage.

## Reusing completed bootstrap builds

`scripts/bootstrap-fingerprint.py` hashes the entire bootstrap closure as one
unit. The key `bootstrap-v1-linux-64-<SHA256>` includes:

- Bootstrap membership/order and every file under each member recipe, including
  patches, tests, build scripts and vendored inputs.
- Literal local source paths referenced by those recipes, including sources
  outside their own recipe directory.
- Seed manifest, Pixi manifest/lock, all variants, repository scripts and the
  package workflow (including runner label, pinned actions and Pixi version).
- Git ignore/submodule configuration and retired package policy when present.

Names, executable bits and file bytes contribute to the hash. Commit IDs,
ordinary recipe contents, documentation and ignored generated output do not.
Script changes are deliberately conservative: even changes to orchestration
checks invalidate the cache. New non-ignored inputs count before being
committed, matching local planner behavior. Unsupported templated local paths,
symlinks or submodule inputs fail closed instead of silently omitting their
content; extend the fingerprint reader before introducing those inputs. The
runner label is hashed, not GitHub's changing image contents. Bump the
fingerprint/cache version when an external environment or policy change requires
a forced rebuild.

When bootstrap is selected, plan restores only an exact cache key, extracts the
selfhost channel and validates its input hash plus every sealed file checksum.
An invalid restored channel fails planning; it cannot be published. A valid hit
is uploaded as this run's normal selfhost-channel artifact.
Dirty/result/selfhost are intentionally skipped, while smoke still executes the
independent package tests and channel checks. Ordinary builds and publication
then follow the same artifact handoffs as a fresh build. The final gate
distinguishes those planned compilation skips from failed or unexpectedly
skipped tests.

On a miss, all three compilation stages run normally. Smoke saves the archived
selfhost channel through actions/cache/save only after all its tests succeed,
before ordinary builds run. A later ordinary-package failure therefore leaves a
usable bootstrap cache for the next run. No dirty/result partial stages, build
trees or installed environments are cached. Cache eviction or unavailable cache
entries simply trigger a full rebuild. There are no restore-key fallbacks.
GitHub's normal branch scope applies: a PR can read default-branch caches and
its own PR caches, but a cache saved by a PR is not shared with main or other
PRs. Pixi's existing environment cache remains separate.

An ordinary-only plan still uses the published channel and does not restore or
rebuild bootstrap. Local entry points always perform their requested stages;
GitHub cache lookup/save is confined to the workflow.

## Local entry points

The complete local commands remain available:

```bash
pixi run bootstrap
pixi run bash scripts/affected-build.sh BASE_SHA
```

Standalone bootstrap writes .build-output/bootstrap-plan.json and runs the same
four stage commands, promoting selfhost output after tests. affected-build.sh
runs planning, the required stages and ordinary builds, then assembles result.
For individual stages use a previously generated plan:

```bash
export PLAN_FILE="$PWD/.build-output/affected-plan.json"
pixi run bash scripts/affected-plan.sh BASE_SHA
pixi run bash scripts/bootstrap.sh dirty
pixi run bash scripts/bootstrap.sh result
pixi run bash scripts/bootstrap.sh selfhost
pixi run bash scripts/bootstrap.sh test
pixi run bash scripts/build-ordinary.sh
```

Each stage resets only its own output. A failed input validation leaves the
existing destination untouched. Source caches retain stable output/<recipe>
paths locally; each recipe still starts with a clean build tree. A stage retry
rebuilds the full stage, rather than resuming from partially produced packages.
All build/publication scripts and the channel handoff utility are global planner
inputs, so changes conservatively request the complete generation and consumers.

## Validation

pixi run pipeline-test exercises real stage scripts with fake build/solver
commands, without downloads or compiler work. It covers stage channel selection,
upstream test flags, deferred independent tests, fresh-runner input
availability, retry isolation, corrupted artifacts, commit/plan/seed mismatches,
ordinary-only and bootstrap-plus-ordinary paths, publication assembly, mixed
stage attempts, planning outputs and failure/cancellation/skip propagation. It
also checks fingerprint invalidation, cross-commit cached selfhost testing and
ordinary publication, and cache-hit compilation skips without skipping tests.
Checks also runs the existing dependency graph tests; actionlint validates
workflow syntax and expressions. These checks establish orchestration behavior,
not a completed multi-job bootstrap build. Full builds remain CI validation.
