# Devkit channel workspace

This repository builds an independent development-tool conda channel for Linux
x86_64 using Clang/LLVM. `osx-arm64` support and stable release promotion remain
planned work.

The channel uses canonical package names and does not aim to make its toolchain
co-installable with conda-forge's toolchain stack in the same environment.

Package outputs, versions, dependencies and tests are defined by
[`recipes/`](recipes/). [`seed-packages.tsv`](seed-packages.tsv) defines the
imported seed; [`bootstrap-order.json`](bootstrap-order.json) defines bootstrap
membership and order. Ordinary build scheduling uses rendered recipe metadata.

See [usage notes](docs/usage.md) for channel-specific user configuration,
[installation policy](docs/development-layout.md) for the shared layout, and
[package CI](docs/package-ci.md) for stage and artifact operations.

Recipe features use conda-forge as the baseline. Preserve enabled features where
possible; a smaller bootstrap closure alone does not justify disabling them.
Compare actual upstream and conda-forge options before claiming parity. Discuss
necessary reductions and their user-visible impact with the maintainer first.
Design reasons and feature investigations live beside the affected recipes.
Cross-recipe questions remain in the [open review](docs/recipe-review.md).

Bootstrap validation must cover the complete seed-free build and runtime
dependency closure. Building an ordered list of tools or passing focused package
tests does not establish a self-hosting fixed point.

## Design goals

- Keep the bootstrap fixed-point explicit and auditable.
- Produce native toolchain interfaces that behave like distribution toolchains
  rather than conda-forge's hermetic compiler target.
- Use canonical package names; do not introduce a private package-name prefix.
- Treat external language toolchains as exact build inputs, not as packages that
  every finished application must carry at runtime.
- Derive package dependency graphs from rendered recipe metadata instead of
  maintaining a second graph by hand.
- Rebuild conservatively. Output-equivalence pruning can be added later, but it
  is not part of the initial release policy.
- Separate bootstrap generations from the stable channel so bootstrap changes
  can be validated before users see them.

## Repository layout and graph boundaries

- `recipes/<name>/`: recipe-owned sources, patches, build scripts and tests.
- `bootstrap-order.json`: ordered bootstrap membership.
- `retired-packages.json`: explicitly retired outputs; unlisted removal is
  rejected.
- `seed-packages.tsv`: fixed seed archive manifest; update deliberately.
- `variants/`: stage-specific recipe configuration.
- `scripts/`: bootstrap, graph, validation and publication entry points.
- `.github/workflows/`: repository checks and package CI.
- `pixi.toml` and `pixi.lock`: orchestration tools and their locked environment.
- `channels/` and `output/`: generated channels, builds and source caches;
  ignored.

Formatting configuration links into the `.format` submodule. Do not commit
package archives, generated repodata, build directories or tool caches.

Recipes share a flat namespace. Directory names are navigation only; rendered
package outputs are dependency-graph nodes. Multi-output recipes build as atomic
units. Bootstrap cycles are contained in a single generation supernode ordered
by the manifest. Cycles outside it and bootstrap dependencies on ordinary
recipes are rejected.

## Dependency graph tooling

The rendered-recipe graph tooling lives in `scripts/dependency-graph/`. Local
checks and package CI share the `plan` command. It reports every affected output
and verifies deliberate version/build-number changes; it never edits recipes.

Before preparing a PR, run:

```bash
pixi run bash scripts/dependency-graph/graph plan origin/main
pixi run bash scripts/dependency-graph/graph plan --check origin/main
```

The base is the merge base of the requested commit and `HEAD`. The comparison
includes committed, staged, unstaged, and untracked (non-ignored) recipe
changes, so developers can rerun it while adjusting build numbers. `--check`
exits nonzero for missing revisions; without it the report remains available for
planning. Use `--json` for machine-readable output, including old/new versions,
build numbers, and per-output errors. Keep the remote base current before
preparing a PR; CI checks against the event's base commit again.

The renderer invokes each recipe with `rattler-build build --render-only`,
without solving or downloading dependencies. It uses the final Linux variant,
maps package outputs to nodes, and reads declared build, host, run,
run-constraint, and test requirements. Declared local run exports contribute
conservative edges from their referenced providers to the exporting package
(self exports add no edge), so provider changes propagate through exporters to
consumers. Ignore rules do not prune this conservative graph. Actual solving,
export application, and version compatibility checks happen during the build.

Impact analysis combines base and working-tree edges, so removing a dependency
cannot hide an affected consumer. Scheduling uses only current edges. Selecting
an output selects all sibling outputs in its recipe; recipes are then sorted as
atomic build units. The explicit bootstrap generation is one unit, internally
ordered by `bootstrap-order.json`. Cycles outside that unit and bootstrap
dependencies on ordinary recipes are rejected.

The existing explicit-root and audit commands remain available:

```bash
pixi run graph-audit
pixi run bash scripts/dependency-graph/graph affected recipes/clang
```

All graph commands accept `--json`. The tool's Python environment is managed
separately by `uv` through `scripts/dependency-graph/pyproject.toml` and
`uv.lock`; Pixi supplies `uv` itself. There are no third-party Python runtime
dependencies.

## Migration plan

The current migration first validates the LLVM bootstrap closure, then its
result-only rebuild, and then all ordinary recipes and affected-build CI.
Default compiler behavior and explicit channel behavior are checked separately.
Unexpected design constraints are discussed before broadening the
implementation.

macOS, release manifests and promotion remain later work. A completed seed build
does not establish a verified self-hosting fixed point.

## Platform and compiler policy

### Linux

Linux uses Clang, LLVM binary tools, LLD, and the Rocky sysroot:

- Clang and the LLVM runtimes are bootstrapped from the fixed seed.
- The normal compiler interface integrates with the host distribution by default
  and does not embed a sysroot.
- Channel builds explicitly request the local sysroot, assembler, and linker.
- The current build baseline is glibc 2.28 from Rocky Linux 8.10.

The native target triplet is:

```text
x86_64-pc-linux-gnu
```

The `pc` vendor field intentionally avoids conda-forge's
`x86_64-conda-linux-gnu` target namespace. It does not define a different x86_64
Linux/glibc ABI.

### macOS arm64

`osx-arm64` support is planned, but the platform strategy is still pending. The
compiler, SDK, and minimum host interface choices have not been fixed yet.

## Language toolchain policy

External language toolchains are exact build inputs. Finished applications only
carry them as runtime dependencies when their functionality requires them.

Rust builds use the exact version recorded by `rust-toolchain-lock`, with
build-local Rustup and Cargo state. Do not request floating toolchains such as
`stable`, `nightly`, or an incomplete version. Changing the lock rebuilds its
reverse dependency closure. The scoped LLVM-libgcc preload needed by upstream
Rust tools belongs in the recipe's build subprocesses; installed applications
and package tests use RUNPATH.

Go builds keep module, build and temporary caches local to the source tree and
use the selected channel toolchain without automatic toolchain downloads.
Applications must not ship those caches.

Python tools use package-owned private environments with exact runtime and
transitive dependency pins. Update constraints and source URLs/hashes together.
Keep uv's directory overrides build-local, exclude caches, and test entrypoint,
symlink and receipt relocation at a different prefix. Native wheel tags must
match the selected interpreter and host ABI floor. These packages depend on the
exact Python runtime and are platform-specific rather than `noarch: python`.

## Package installation policy

The [shared layout policy](docs/development-layout.md) defines private runtime
and development directories, versioned headers, metadata and RUNPATH rules.
Explain recipe-specific exceptions beside their implementation.

Target-package builds resolve only against the applicable local stage/ordinary
overlay and the selected devkit channel inputs. Conda-forge is not a target
fallback. The hosted channel must not declare a CEP 42 base or override
relation: rattler-build follows those relations recursively. The locked Pixi
environment is a separate orchestration layer and may use external tools.

## Rebuild and release policy

The near-term policy is intentionally simple because the channel is small: once
an input enters the affected closure, rebuild it and all of its direct and
transitive consumers. We do not try to predict whether a dependency change
actually alters a downstream artifact.

The initial scheduler design deliberately does not compare old and new package
payloads to decide whether publication can be skipped. A changed build input may
produce the same bytes, but proving that equivalence safely requires a
normalized logical comparison and is deferred.

The current Linux scheduler validates the selected closure by rebuilding it in
pull requests and uploads the generated archives after the change reaches
`main`. Before any package build, CI checks every selected output against the
base: an unchanged software version requires a strictly larger build number and
a changed build string. A new output or changed software version may start at
build 0. Developers make these changes explicitly, including all affected
consumers and sibling outputs. CI does not rewrite recipes. Publishing an
existing filename remains an error rather than an overwrite. Release manifests
and candidate-channel promotion remain future work.

The initial rules are conservative:

- A bootstrap input change reruns the complete Linux bootstrap and then rebuilds
  ordinary Linux packages affected by the new generation.
- A Rust toolchain lock change rebuilds all Rust-using packages.
- A Go toolchain change rebuilds all Go-using packages.
- A Python runtime change rebuilds all Python tool packages.
- A shared C library change rebuilds its reverse runtime/build dependency
  closure.
- A leaf tool source change rebuilds that tool.
- Every package submitted for publication has a deliberate version or build
  number change; release promotion remains future work.

The reverse dependency graph is derived from the repository's rendered recipe
metadata. Published channels solve and overlay unchanged packages; they are not
a second hand-maintained graph source.

### Calculating the affected rebuild set

The affected-build scheduler uses the same flat recipe namespace as the
repository. It computes affected Linux builds and constructs a directed graph
before scheduling:

1. Discover every `recipes/*/recipe.yaml`.
2. Load the explicit bootstrap membership manifest and set those recipes aside
   as the bootstrap generation supernode.
3. Render all recipes without solving, using their intended variant
   configuration.
4. Make every rendered package output a graph node. A multi-output recipe
   contributes multiple nodes; its directory name is not a package node.
5. Add an edge from a dependency provider to each direct consumer. Build and
   host requirements create build-time edges; run requirements create runtime
   edges. Rendered `run_constrained` specifications are initially treated as
   conservative interface edges as well.
6. Treat a `noarch` output as shared by all target platforms.
7. Reject strongly connected components outside the explicit bootstrap set.

The initial rebuild roots are the package outputs changed by a commit. A change
under a recipe directory, except its root `README.md`, initially selects all
outputs of that recipe. Changes to explicit global bootstrap inputs select every
recipe; workflow and documentation changes do not schedule package builds.
Refinement to individual outputs can be added only when the mapping is explicit
and auditable. The completed-stage test runner and shared build-output cleanup
helper are global bootstrap inputs as well.

The scheduler traverses reverse dependency edges from those roots. Every direct
and transitive build-time, runtime, and constraint consumer will be selected.
The selected set will be topologically scheduled with providers before
consumers.

Bootstrap changes are checked and scheduled as part of this graph. A change to
the seed manifest, bootstrap membership, bootstrap stage ordering, or a
bootstrap recipe selects the complete bootstrap generation and its ordinary
consumers before any build starts. After revision validation, the complete
generation is rebuilt. Bootstrap cycles are permitted only inside that explicit
generation supernode.

The pull-request path classifier is deliberately explicit. A recipe's root
`README.md` contains design or usage notes and does not select package builds.
Other files under `recipes/`, including Markdown files in source/test trees,
select that recipe. The dependency-graph planner and its tests under
`scripts/dependency-graph/` also do not select builds: they control scheduling
and are validated by repository tests rather than becoming target payloads.
Changes to global inputs, including `bootstrap-order.json`, `variants/`,
`seed-packages.tsv`, the Pixi manifest/lock, the package workflow and other
repository scripts, select every recipe. Recipe deletion or rename is not
supported yet and must be rejected rather than silently treated as a no-op.

The locked Pixi environment is an orchestration layer rather than a target
package dependency. Its manifest and lock nevertheless count as global planner
inputs because tool changes can alter package output; pair those changes with
the required recipe version/build-number updates.

A single PR can introduce a new dependency and its consumers. Planning needs no
published copy of that dependency. Each completed recipe is indexed into the
local result channel before its consumers are solved, with strict priority over
the published baseline. If a consumer's version constraint excludes the new
local provider, the build fails; update the constraint together with the
provider.

Dependencies may use names or compatibility ranges; exact version/build pins are
not required by the planner. Retain exact pins where the toolchain, ABI, or a
private Python environment requires them. Existing recipe pins are not relaxed
automatically; revise them deliberately when updating their providers.

The graph conservatively matches local providers by package name, regardless of
version constraints. It does not expand the published channel's solved
dependency closure or external run exports. Changes only in external channel
contents do not trigger rebuilding. Multiple variants of the same package name
remain unsupported. Revision checks are relative to Git, not a reservation of
filenames in the published channel; concurrent PRs must be brought up to date
before merge.

The `h<hash>` portion of a build string identifies variant parameters, not
source contents or the complete resolved dependency set. Changing a literal
dependency constraint need not change that hash. It does not replace the
build-number bump.

For example, a `go` change selects every package with a direct or transitive
build edge to `go`. A `python` runtime change selects Python tools through
runtime edges and then selects their consumers through the merged reverse graph.
A leaf change to `ripgrep` selects `ripgrep` alone unless another recipe depends
on it.

Reproducibility is a later design phase, not a prerequisite for the initial
scheduler. If reliable logical reproducibility is achieved, result comparison
could become the primary pruning mechanism: build an affected provider, compare
its normalized logical digest with the published artifact, and propagate only
when the output or package interface differs. That approach may replace the
present conservative propagation model rather than merely optimize it. Such a
comparison must cover payload paths, hashes, permissions, symlink targets,
runtime dependencies, constraints, and `run_exports`; archive-level SHA equality
alone is insufficient. Until that mechanism exists, a changed dependency means a
rebuild.

Release manifests should eventually record:

- the recipe commit;
- target platform and generation identifier;
- toolchain input versions;
- package filenames and SHA-256 hashes;
- rendered dependency graph snapshots;
- whether each rebuilt artifact was retained or published.

## Reproducibility

The bootstrap uses locked source archives, locked build tools, explicit stage
channels, and deterministic recipe ordering. This provides reproducible inputs
and a repeatable bootstrap process.

It is not yet a claim of byte-for-byte `.conda` reproducibility. Conda archive
timestamps, embedded recipe timestamps, build-directory paths, and channel URLs
can differ between builds. Prefix relocation and `info/paths.json` still make
installed payload hashes useful for future logical comparisons.

Any later output-equivalence mechanism must normalize those differences and must
not rely on archive-level SHA equality alone.

## Bootstrap generation model

The generated channels represent stages, not the eventual public release layout:

```text
channels/seed     Fixed imported bootstrap input
channels/dirty    Compiler carrier built from the seed
channels/result   Self-hosted result generation
```

The eventual channel roles may resemble:

```text
devkit-bootstrap-<generation>   Verified internal bootstrap generation
devkit-next                     Candidate release channel
devkit                          Stable user channel
```

Names above are channel names, not conda package-name prefixes. Bootstrap
artifacts should not be promoted merely because they were built; promotion
should consume a release manifest and a successful verification run.

## Running the bootstrap

The new full bootstrap driver is implemented but its complete fixed point is
still under validation. After installing Pixi, its entry point is:

```bash
pixi run bootstrap
```

This is the canonical command. It removes generated dirty/result channels and
compilation outputs while retaining seed archives and the per-recipe
Rattler-Build `src_cache/` directories. A recipe's output directory is shared by
all bootstrap stages, so later stages reuse its downloaded sources but still
compile in a freshly cleaned build directory. Package-manager caches use their
tool defaults. The bootstrap verifies and indexes the seed, builds and publishes
the dirty and result stages, reruns the result-only fixed point, and executes
the result checks, including an actual result-only installation and both
compiler-policy probes. These probes require host GCC development files. Every
stage follows `bootstrap-order.json`; only its visible channels and variant
configuration change between stages.

The Pixi environment provides `rattler-build`, `rattler-index`, mamba, and the
archive tools required by the scripts. The direct script is also available when
that environment is already active, or when `RATTLER_BUILD` points to a suitable
executable and the remaining tools are on `PATH`:

```bash
./scripts/bootstrap.sh
```

Individual checks are available through:

```bash
pixi run check-seed
pixi run check-result
```

Local channels passed to rattler-build should use an explicit `./` prefix, for
example `./channels/result`. A bare relative path can be interpreted as a named
remote channel.

### GitHub Actions

Repository checks live in `.github/workflows/checks.yml`. That workflow runs on
pushes to `main`, pull requests, a weekly schedule, and manual dispatch. It runs
the shared generic checks (cleanliness, dependency-update coverage, REUSE
metadata, secret scanning, and PR commit linting), formatting checks backed by
`.format`, and the dependency-graph unit tests:

```text
pixi run graph-test
```

Package builds live in `.github/workflows/packages.yml`. A planning job checks
version/build-number revisions and calculates the affected closure once. Three
separate bootstrap jobs build dirty, result and selfhost, followed by a job for
independent package tests and channel smoke checks, then a job for selected
ordinary packages. Each execution job has its own six-hour limit. Bootstrap
stages are skipped when only ordinary recipes change; all execution jobs are
skipped when no target packages change.

The plan travels as an artifact and small job outputs control scheduling.
Channel artifacts contain archives, repodata, relative package manifests and
checksums tied to the bootstrap inputs, or to the checkout and plan for ordinary
outputs. Exact bootstrap cache hits skip the three compilation jobs and still
run independent tests and smoke checks. Only successfully tested selfhost
channels enter the cache; a miss rebuilds normally. Each runner creates fresh
environments; no installed environment or build tree is transferred. Ordinary
output remains separate from the immutable, tested selfhost input. Publication
verifies and merges the required artifacts into channels/result. Intentional
skips pass the final gate; failures, cancellations and unexpected skips do not.

Pull requests validate without publishing. Main pushes retain prefix.dev OIDC
trusted publishing after every required build and test succeeds. The workflow
remains independent of repository checks and does not use PREFIX_API_KEY.
Planning and stage outcomes appear in job summaries. Artifacts are retained for
three days and logs remain available through Actions.

See [the stage interfaces and artifact protocol](docs/package-ci.md) for input
channels, skip rules, local commands and validation. `pixi run bootstrap` and
`scripts/affected-build.sh BASE_SHA` remain local one-command entry points using
the same independently executable stages as CI.

## Package splits and compatibility names

Content-bearing packages own complete upstream installations. Where a seed or
consumer requires a split name, provide a file-free compatibility output with an
exact dependency on the content-bearing sibling. Do not reproduce upstream file
splits solely to match package names or introduce file collisions.

Content-bearing build strings use `h<variant-hash>_<build-number>`;
metadata-only interfaces use the `meta_` prefix. Dirty-stage runtime aliases
follow the
[bootstrap compatibility policy](docs/development-layout.md#bootstrap-compatibility).

## Compiler interfaces

Normal Clang invocations use host development files and the host linker. Channel
builds explicitly load `lib/devkit/share/devkit/clang.cfg` with
`--no-default-config`, and opt into private dependency discovery. See
[compiler design](recipes/clang/README.md) for the reasons for these two modes
and [usage notes](docs/usage.md#compiler-modes) for invocation examples.

## Known gaps before stable promotion

- Design and add `osx-arm64` builds; the compiler and SDK strategy is pending.
- Define remote retirement/publication semantics beyond the explicit local
  retirement manifest. Unlisted deletion and rename remain rejected.
- Extend graph rendering to multiple platforms and multiple variants per output.
- Add channel-wide filename collision checks and release promotion.
- Add release manifests and promotion scripts.
- Decide whether `tzdata` remains an imported data-only exception or becomes a
  local package.
- Replace current Rocky Linux mirror URLs with immutable vault URLs if archive
  stability requires it.
- Pin Pixi in CI and run the workflow in locked mode.
- Complete LLVM self-hosting and ordinary-package runtime audits, including
  execution on hosts with older system runtimes.
- Define and test the oldest supported host glibc baseline.

## Bootstrap-stage command reference

For individual experiments use `rattler-build build --no-config`, the dirty or
result variant file, and explicit local channels. Dirty uses dirty then seed;
result uses completed dirty only; the final rebuild uses completed result only.
Index each output before a dependent build and avoid stale generation archives.
Seed GNU libgcc remains public while LLVM-libgcc installs privately. No
seed-derived libgcc variant or replacement meta package is needed. Dirty
libraries supply public SONAME compatibility links for seed tools; result and
selfhost omit those links. The focused seed runtime check is
`bash scripts/check-seed-llvm-runtime.sh INSTALL_PREFIX`.

After installing a complete compiler/runtime/sysroot environment, run:

```bash
bash scripts/check-clang-policy.sh INSTALL_PREFIX
bash scripts/check-clang-channel.sh INSTALL_PREFIX
```

The first check requires host GCC development files. The second verifies the
explicit channel configuration without loader overrides.

Stage channels, test scheduling and artifact handoffs are described in the
[package CI reference](docs/package-ci.md). Installed tests compile consumers
against the completed test environment; they must not carry build-stage probe
executables into another stage. Source build-tree tests are separate and honor
`DEVKIT_RUN_TESTS` without reducing final-stage workloads.
