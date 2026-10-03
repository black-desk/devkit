# Devkit channel workspace

This repository currently contains a reproducible `linux-64` GCC bootstrap and
is the seed of a small, independently maintained conda channel for development
tools. The intended platforms are:

```text
linux-64
osx-arm64
```

The project is not a conda-forge overlay. Existing and future packages use
canonical names such as `gcc`, `gxx`, `go`, `python`, and `rustup`, and the
channel does not attempt to make its toolchain packages co-installable with
conda-forge's toolchain stack in the same environment.

## Current status

The Linux bootstrap is working end-to-end:

1. A fixed conda-forge-derived seed is downloaded and verified from
   `seed-packages.tsv`.
2. A Rocky Linux 8.10-derived `sysroot_linux-64` is built first in the dirty
   stage, using the seed-compatible `x86_64-conda-linux-gnu` layout.
3. A dirty GCC carrier is built with the seed compiler interfaces and the dirty
   sysroot, then exposed through local `gcc` and `gxx` interface packages.
4. Local binutils, GNU Make, and gnuconfig are built through those interfaces.
5. The same recipe order is rebuilt as the result generation against the result
   sysroot and dirty compiler interfaces.
6. A result-only fixed-point rebuild passes the embedded GCC tests and produces
   a compiler installation that no longer depends on the seed channel.

Installing the current result interface:

```text
gcc gxx binutils make gnuconfig sysroot_linux-64
```

resolves eight packages from the local result channel:

```text
gcc
gxx
gcc-toolchain
binutils
make
gnuconfig
sysroot_linux-64
tzdata
```

`tzdata` is currently the one imported conda-forge package in that closure. It
is an explicitly retained data-only exception while the bootstrap is being
developed; it should either be documented as permanent or replaced by a local
package before the first public stable channel.

The current seed contains 22 archives, principally GCC/G++ 14.4.0, binutils
2.46.1, glibc 2.28 bootstrap interfaces, GNU Make 4.4.1, Linux 4.18 kernel
headers, gnuconfig, and their metadata dependencies. Exact URLs, sizes, and
SHA-256 hashes are recorded in `seed-packages.tsv`.

The first ordinary toolchain input is a version-pinned repack of the official
Linux/amd64 Go distribution. Its official GOROOT layout is retained below
`lib/go/<version>/`, with `go` and `gofmt` linked from `bin/`. `lazygit` is the
first normal tool recipe; it declares the channel's `git` package as a runtime
dependency so installation includes Git on `PATH`. The canonical `rustup`
manager is also packaged as an official binary repack without a selected Rust
toolchain. The tools built from that locked Rust input currently include
`ripgrep`, `fd`, and `uv`. macOS builds and a release promotion process are
still incomplete. The Linux package workflow has an initial affected-build
scheduler for the current bootstrap recipes and these ordinary packages.

`difftastic` is also built from the locked Rust toolchain input.

The `uv` recipe builds uv 0.12.22 and its `uvx` launcher from source, with Bash,
Fish, and Zsh completions. It uses the locked Rust toolchain and local
GCC/binutils/Make/sysroot for its native dependencies. The release build keeps
the upstream performance allocator, uses thin LTO to reduce build memory, and
disables self-update so upgrades remain owned by the channel. The package does
not include a Python interpreter. Its offline package tests cover both
executables, custom installation directories, project initialization, and the
bundled Python download metadata. The Linux binaries use the host glibc and
`libgcc_s.so.1`; their required symbol versions are no newer than `GLIBC_2.28`
and `GCC_4.2.0`.

The `python` recipe packages CPython 3.14.8 from the `python-build-standalone`
20261001 release. Rattler-Build verifies the pinned archive, then uv 0.12.22
installs it from a local mirror without network access. The distribution stays
under `lib/uv-python/`, with `python`, `python3`, and `python3.14` exposed in
`bin/`. It retains the bundled standard library, headers, shared Python library,
and pip; uv is a build dependency only. Package tests check relocated
interpreter and sysconfig paths, native standard library modules, virtual
environments with pip, and offline uv tool installation.

The first independent Git dependencies are packaged as ordinary C libraries with
isolated headers: `zlib`, `pcre2`, `expat`, and `openssl`. The pinned Mozilla CA
bundle is packaged separately as `ca-certificates` for HTTPS support. OpenSSL's
Perl-based build system uses the local `perl` interpreter.

The `git` recipe builds Git 2.56.0 with the locked Rust input, HTTPS through
local curl/OpenSSL and the CA bundle, PCRE2, Perl scripts, and
`contrib/subtree`. It disables Tcl/Tk, Python helpers, and gettext. Its package
tests cover basic repository operations, PCRE2 grep, worktrees, subtree, and
local shared-library resolution. Some optional Perl commands, such as `git svn`
and SMTP delivery with `git send-email`, require additional modules not
currently packaged here. Installing `lazygit` also installs this Git package;
its package tests check Git's path and basic repository initialization.

During channel bring-up, recipes favor completing the applications that the
channel is intended to provide over exhaustively enabling every upstream
optional feature. Library recipes select the smallest explicit dependency set
needed by those applications and disable unsupported extras. A later release
line will review each library's build options individually; that review must
record the chosen options and use the normal version/build-number and affected
rebuild process.

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

## Current layout

```text
.format/                 Shared formatting configuration submodule

.github/workflows/
  checks.yml            Generic, formatting, and dependency-graph checks
  packages.yml          Affected package builds and prefix.dev publication
.github/dependabot.yaml Dependency-update policy used by repository checks

bootstrap-order.json    Ordered bootstrap recipe membership

recipes/
  gcc-toolchain/        Coarse single-package GCC/G++ carrier
  gcc-aliases/          gcc and gxx interface outputs
  binutils/             Native assembler, linker, and binary tools
  ca-certificates/      Pinned Mozilla CA certificate bundle
  expat/                Stream-oriented XML parser library
  make/                 GNU Make carrier
  git/                  Git with Rust, HTTPS, PCRE2, Perl scripts, and subtree
  gnuconfig/            Pinned config.guess and config.sub
  openssl/              TLS and cryptography library
  pcre2/                Perl-compatible regular expression library
  perl/                 Perl interpreter and core modules
  sysroot/              Rocky Linux 8.10-derived Linux sysroot
  go/                    Official Go linux-amd64 distribution repack
  lazygit/               Terminal UI for Git commands
  fd/                    Fast filesystem search tool
  ripgrep/               Fast regex search tool
  difftastic/            Syntax-aware structural diff tool
  pkgconf/               pkg-config-compatible metadata query tool
  rustup/                Official Rust toolchain manager binary repack
  python/                CPython standalone distribution installed by uv
  uv/                    Python package, tool, and interpreter manager
  zlib/                  General-purpose compression library

variants/
  dirty.yaml            Seed-compatible bootstrap variant
  result.yaml           Result sysroot and target-triplet variant

scripts/
  bootstrap.sh          Reset build outputs, fetch, build, index, and verify
  affected-build.sh     Build the recipes affected by a pull request or push
  dependency-graph/     Rendered recipe graph and affected-closure calculator
  publish-result.sh     Upload generated result archives to prefix.dev
  fetch-seed.sh         Download and verify the fixed seed
  check-seed.sh         Check offline solvability of the seed channel
  check-result.sh       Check the result-only build-tool interface

channels/               Generated local channels; not committed
output/                 Generated per-recipe builds and source caches; not committed
seed-packages.tsv       Fixed seed archive manifest
pixi.toml               Locked bootstrap tool environment definition
pixi.lock               Locked bootstrap tool versions

The formatting entry points `.black.toml`, `.clang-format`, `.editorconfig`,
and `.prettierrc` are repository symlinks into the `.format` submodule.
```

`pixi.toml` and `pixi.lock` are repository files, not members of `scripts/`.
`seed-packages.tsv` is the authoritative seed manifest and must be changed
deliberately. Seed archives, package outputs, source caches, generated repodata,
and local channel contents are deliberately ignored.

## Recipe organization and graph boundaries

The long-term organization remains a single recipe monorepo, but recipes are not
divided into bootstrap, toolchain, and tool directories. Those categories are
frequently ambiguous—`gcc` is both a bootstrap artifact and the public compiler
interface, while `python` is both a language runtime and a build input—and they
must not become inputs to build scheduling.

The intended layout is:

```text
recipes/
  aerc/
  binutils/
  ca-certificates/
  difftastic/
  expat/
  fd/
  gcc-aliases/
  gcc-toolchain/
  git/
  gnuconfig/
  go/
  lazygit/
  make/
  neovim/
  notmuch/
  openssl/
  pcre2/
  perl/
  pkgconf/
  python/
  ripgrep/
  rust-toolchain-lock/
  rustup/
  sysroot/
  typst/
  uv/
  zlib/

platforms/
  linux-64/
  osx-arm64/

scripts/
  dependency-graph/     Rendered dependency graph tooling

releases/
  manifests/
```

Recipe directories are navigation and source-layout names only. Package names
remain canonical: the recipe in `recipes/go/` produces `go`, and the recipe in
`recipes/python/` produces `python`. Bootstrap-only names such as
`gcc-toolchain` exist to support staged self-hosting and compatibility with the
imported seed; they are not a general naming convention.

For ordinary packages, the build graph is derived from rendered recipes. Each
package output is a graph node, so a multi-output recipe contributes its actual
output names rather than a directory name. Direct dependency specifications form
the edges; a complete resolved closure is not expanded into direct edges.

Bootstrap membership is explicit rather than inferred from a directory. It is
represented by `bootstrap-order.json`, a top-level JSON array of recipe
directory names. `scripts/bootstrap.sh` executes that order in each stage; the
dependency-graph prototype reads the same array as the bootstrap generation
membership. Stage-specific variants and channel boundaries remain part of the
bootstrap and graph entry points rather than the recipe namespace.

The bootstrap recipes are special. Collapsing their staged package names can
produce cycles between GCC, binutils, and Make. They are therefore handled as a
bootstrap generation supernode rather than fed directly to the ordinary
topological scheduler. Outside bootstrap, SCCs should be rejected.

## Dependency graph tooling

The rendered-recipe graph tooling lives in `scripts/dependency-graph/`. It does
not bump build numbers or publish packages. Pull-request CI uses its `affected`
report as the source of build scheduling input.

The renderer invokes each recipe with
`rattler-build --render-only --with-solve`, using the final Linux generation's
variant and either the local result channel (for audit commands after a local
bootstrap) or the published Linux baseline channels (for pull-request
scheduling). It maps rendered package outputs—not recipe directory names—to
graph nodes, adds direct build, host, run, and constrained-run edges, records
dependencies that resolve outside the local graph, and rejects SCCs outside the
explicit bootstrap generation. Selecting any bootstrap output expands the
generation to its complete membership and schedules those outputs according to
`bootstrap-order.json`.

After a successful bootstrap:

```bash
pixi run graph-audit
pixi run bash scripts/dependency-graph/graph affected recipes/gcc-toolchain
```

Both graph commands accept `--json` for machine-readable reports. The tool's
Python environment is managed separately by `uv` through
`scripts/dependency-graph/pyproject.toml` and `uv.lock`; Pixi supplies `uv`
itself. The current prototype has no third-party Python runtime dependencies.

## Migration plan

The intended migration is incremental:

1. Preserve the verified Linux bootstrap, its flat recipe layout, and its
   explicit `bootstrap-order.json` stage ordering.
2. Harden the recipe renderer and dependency graph as ordinary packages are
   added.
3. Introduce canonical `go`, `rustup`, `rust-toolchain-lock`, `python`, and `uv`
   toolchain packages with build-local caches and exact version inputs.
4. Add ordinary tool recipes on top of the rendered graph and affected-build CI.
5. Add `osx-arm64`; its platform and compiler strategy is still to be designed.
6. Add candidate and stable release channels, manifests, and promotion checks.

At every step, the existing Linux bootstrap remains the reference fixed point
until a new bootstrap generation has completed the same verification.

## Platform and compiler policy

### Linux

Linux continues with the local GCC/binutils/sysroot bootstrap:

- GCC and binutils are self-hosted from the fixed seed.
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

The Go distribution, rustup manager, Rust toolchain lock, Python, and uv recipes
are current. Their detailed consumer policies and the remaining language-runtime
recipes below are target design unless a current recipe says otherwise.

External language toolchains are exact inputs to CI builds. Finished native
tools do not depend on their compiler manager at runtime.

### Rust

The channel packages `rustup` normally, but does not package generic `rustc` or
`cargo` outputs as though they were the selected toolchain.

A separate `rust-toolchain-lock` package records the exact selected Rust
toolchain. It is currently pinned to Rust `1.98.1`. Rust-using recipes declare
these packages as build dependencies and install that exact toolchain into
build-local state:

```bash
export RUSTUP_HOME="${SRC_DIR}/.rustup"
export CARGO_HOME="${SRC_DIR}/.cargo"
export CARGO_TARGET_DIR="${SRC_DIR}/target"

RUST_TOOLCHAIN="$(cat "${BUILD_PREFIX}/share/rust-toolchain/version")"

rustup toolchain install "${RUST_TOOLCHAIN}" \
  --profile minimal \
  --no-self-update

rustup run "${RUST_TOOLCHAIN}" cargo build \
  --release \
  --locked
```

Toolchain requests must be exact. Ambiguous requests such as `stable`,
`nightly`, or a minor version without a patch are not accepted. Changing the
lock package triggers rebuilding the reverse build-dependency closure.

### Go

The `go` package is a version-pinned repack of the official Go distribution for
each supported platform. The complete official GOROOT is installed below
`lib/go/<version>/`, while `bin/go` and `bin/gofmt` are relative links into it.
Go applications use it as a build dependency only.

Go builds isolate all state below the recipe source directory:

```bash
export GOPATH="${SRC_DIR}/.go-path"
export GOMODCACHE="${SRC_DIR}/.go-mod-cache"
export GOCACHE="${SRC_DIR}/.go-build-cache"
export GOTMPDIR="${SRC_DIR}/.go-tmp"

export GOENV=off
export GOWORK=off
export GOTOOLCHAIN=local
export GOFLAGS="-mod=readonly"
```

Pure Go tools are built with `CGO_ENABLED=0`, `-trimpath`, and
`-buildvcs=false`, and are emitted directly to `$PREFIX/bin`. Neither the Go
toolchain nor its module/build caches become runtime dependencies.

### Python

The canonical `python` runtime package uses `uv python install` with
`UV_PYTHON_INSTALL_DIR=$PREFIX/lib/uv-python` and
`UV_PYTHON_BIN_DIR=$PREFIX/bin`. The recipe pins Python 3.14.8, the
`python-build-standalone` build date 20261001 (`UV_PYTHON_CPYTHON_BUILD`), uv
0.12.22, and the release archive's SHA-256. An explicit source `file_name`
preserves the archive for uv, which installs it offline through a local
`UV_PYTHON_INSTALL_MIRROR`.

The upstream runtime layout and bundled libraries are retained; its
`sys.prefix`, headers, and site-packages live inside the versioned distribution,
not directly at the conda prefix. OpenSSL uses the upstream system certificate
paths, with the usual `SSL_CERT_FILE` and `SSL_CERT_DIR` overrides. The PEP 668
marker identifies the devkit conda channel as the runtime's owner. Use virtual
environments for Python packages; the public `bin/` entries are the three Python
interpreter names, while bundled pip is available as `python -m pip`. Manager
lock files and caches are excluded. Binary relocation is disabled to preserve
the standalone distribution's loader paths; conda still handles prefix text and
symlink relocation.

Python tool recipes will use `uv tool install` to create private environments
below the package prefix, with exact per-platform constraints for the tool and
all transitive dependencies. The intended build-local configuration is:

```bash
export UV_CACHE_DIR="${SRC_DIR}/.uv-cache"
export UV_NO_CONFIG=1
export UV_PYTHON_DOWNLOADS=never
export UV_TOOL_DIR="${PREFIX}/share/devkit/python-tools"
export UV_TOOL_BIN_DIR="${PREFIX}/bin"

uv tool install \
  --python "${PREFIX}/bin/python" \
  --link-mode copy \
  --constraints "${SRC_DIR}/requirements.lock" \
  "${PKG_NAME}==${PKG_VERSION}"
```

The package owns the resulting environment, entrypoints, and per-tool
`uv-receipt.toml`. uv discovers tools and interpreters by their configured
directories; there is no central installation registry to ship. These directory
overrides are only set during the build, not in user activation scripts. A
user's normal `uv tool list`, `uv tool upgrade`, or `uv python uninstall`
therefore does not manage channel-owned files unless the user explicitly points
uv at those private directories. Caches and shared directory lock files are not
packaged. Conda prefix handling must relocate symlinks, entrypoint scripts,
`pyvenv.cfg`, and receipts, with package tests checking a different install
prefix. uv is a build dependency only for these Python and Python tool packages.

Python tool packages have a direct exact runtime dependency on `python` and are
built separately for `linux-64` and `osx-arm64`; they are not `noarch: python`
packages.

## C library packaging policy

Ordinary shared C libraries use canonical upstream package names but expose
their public headers through a package- and version-specific include root. A
library named `foo` at version `1.2.3` installs its headers below:

```text
${PREFIX}/include/foo-1.2.3/
```

It must not install public headers directly below `${PREFIX}/include`. That rule
is intentional: a broad `-I${PREFIX}/include` must never make channel headers
for an unrelated library visible while building against another package.
Consumers use the exact root selected by the library's pkg-config entry:

```bash
CFLAGS="$(pkg-config --cflags foo)"
```

or an explicit equivalent:

```bash
-I${PREFIX}/include/foo-1.2.3
```

Recipes therefore do not add a generic `-I${PREFIX}/include` to `CPPFLAGS` or
`CFLAGS`. When upstream's Makefile, CMake package, or pkg-config metadata
assumes a shared include directory, the recipe overrides the install path or
patches that metadata. In particular:

- pkg-config `Cflags` must point at the version-specific include root.
- pkg-config `Libs` and `Libs.private` must use exact library paths, such as
  `${libdir}/libfoo.so`, rather than exposing `${libdir}` through a broad
  `-L${libdir}` plus an unqualified `-lfoo`.
- pkg-config `Requires` and `Requires.private` must preserve transitive public
  header dependencies.
- exported CMake include paths and imported-target interface directories must
  use the same root; an upstream config that cannot be corrected is not
  installed.
- upstream `foo-config` helpers are corrected rather than deleted, but they are
  package-private build metadata programs rather than user commands.
- tests must compile and run a small consumer without adding the shared
  `${PREFIX}/include` directory to the compiler command line.

Package metadata tests use the channel-owned `pkgconf` package through its
`pkg-config` compatibility name; they do not rely on a `pkg-config` executable
from the build host or the Pixi orchestration environment.

Corrected `foo-config` helpers install below:

```text
${PREFIX}/libexec/<package>/bin/
```

They must not install into `${PREFIX}/bin`. Corrections are made in upstream's
generated-source template whenever practical—for example, an Autotools
`foo-config.in`—so the upstream command-line interface and future options remain
intact. The helper emits the version-specific include root and exact
library-file paths, not a generic `-I${PREFIX}/include`, `-L${PREFIX}/lib`, or
unqualified `-lfoo`.

Downstream recipes do not put these helpers on the public `PATH`. A recipe that
cannot use pkg-config refers to the helper directly—for example,
`${PREFIX}/libexec/pcre2/bin/pcre2-config`—or prepends only that package's
private helper directory inside its own build script. Activation scripts must
not expose these directories globally.

Shared objects and their unversioned development symlinks remain under the
conventional `${PREFIX}/lib` layout with upstream SONAMEs. C library recipes
also declare appropriate ABI `run_exports`, and downstream recipes use direct
dependency specifications rather than expanding a solved closure into their
metadata.

Target-package rendering and builds use only the pull request's local
`channels/result` overlay and `https://prefix.dev/black-desk`. Conda-forge is
not a fallback for target dependencies. The hosted channel must not declare a
CEP 42 base or override relation, because rattler-build discovers and follows
those relations recursively; the affected-build script checks its repodata
before rendering or building. The locked Pixi environment that runs the build
scripts is a separate orchestration layer and may still use external tools until
equivalent channel-owned build tooling exists.

The compiler's internal headers and `sysroot_linux-64` are exceptions to this
layout: they implement the compiler/sysroot interface rather than ordinary
channel libraries.

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
`main`. It does not rewrite recipe build numbers; an unchanged filename is an
immutable publication error rather than an overwrite. Release manifests and
candidate-channel promotion remain future work.

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
  number change and passes through release promotion.

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
3. Render every remaining recipe with its intended channels and variant
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
under a recipe directory initially selects all outputs of that recipe. Changes
to explicit global bootstrap inputs select every recipe; workflow and
documentation changes do not schedule package builds. Refinement to individual
outputs can be added only when the mapping is explicit and auditable.

The scheduler traverses reverse dependency edges from those roots. Every direct
and transitive build-time, runtime, and constraint consumer will be selected.
The selected set will be topologically scheduled with providers before
consumers.

Bootstrap changes are handled before this ordinary graph. A change to the seed
manifest, bootstrap membership, bootstrap stage ordering, or a bootstrap recipe
reruns the complete bootstrap generation. On success, the generation's public
interfaces are used as changed roots in the ordinary reverse-dependency graph.
Bootstrap cycles are permitted only inside that explicit generation supernode.

The pull-request path classifier is deliberately explicit. Changes under
`recipes/` select that recipe. Changes to `bootstrap-order.json`, `variants/`,
`seed-packages.tsv`, or the bootstrap/check scripts select every recipe. Other
workflow, documentation, and Pixi orchestration changes do not schedule target
packages by themselves. Recipe deletion or rename is not supported yet and must
be rejected rather than silently treated as a no-op.

The locked Pixi environment is an orchestration layer, not a target dependency
graph input. If an orchestration tool change is known to alter package output,
it must be paired with explicit recipe version/build-number changes or a
deliberate full-rebuild change. This keeps test-only and build-utility lock
updates from rerunning the expensive bootstrap fixed point automatically.

There is also a known rendering limitation: the graph is rendered against the
published baseline before any package from the pull request is built. A single
pull request that introduces both a new local dependency and its first consumer
can therefore fail to solve until the renderer gains an unpublished-local-output
mode. Adding such a provider in a preceding pull request is the current
incremental workflow.

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

After installing Pixi, run:

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
the result checks. Every stage follows `bootstrap-order.json`; only its visible
channels and variant configuration change between stages.

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

Package builds live in `.github/workflows/packages.yml`. On pull requests, that
workflow derives changed recipe directories from the PR diff, asks the rendered
graph for their conservative reverse closure, and builds that closure. Bootstrap
recipe changes and changes to global bootstrap inputs run the complete seed →
dirty → result → self-host fixed point before building selected ordinary
consumers. Ordinary recipe changes build sequentially through the same
`output/<recipe>/` source-cache layout used by bootstrap, publish into the
generated local `channels/result` overlay, and resolve unchanged baseline
packages from the public `https://prefix.dev/black-desk` channel. Conda-forge is
not a target-dependency fallback. Other repository changes skip package builds.

Pull requests validate the affected closure but do not publish it. After the
pull request is merged to `main`, the package workflow runs against the push
diff, builds the affected closure, and uploads the generated archives in
`channels/result` to `https://prefix.dev/black-desk`. Publication uses
prefix.dev trusted publishing through GitHub Actions OIDC, so `packages.yml` is
the workflow that must be configured as a trusted publisher. The repository does
not store or use a `PREFIX_API_KEY` secret. Immutable package publication
remains intentional.

The package workflow is deliberately independent of the repository-check
workflow. Publication is gated by the affected-build result and pull request
review, not by formatting or generic repository checks.

The package job writes its changed recipe roots, complete rebuild plan, rebuild
result, and produced archives to the GitHub Actions job summary. After a push to
`main`, the publication job appends the archives uploaded to prefix.dev.

## Package roles in the current bootstrap

- `gcc-toolchain` is the coarse compiler carrier. It owns the complete GCC/G++
  installation, compiler runtime libraries, development symlinks, and compiler
  drivers.
- `gcc` and `gxx` are interface packages selecting the carrier. They permit the
  same carrier recipe to operate against seed, dirty, and self-hosted channel
  stages.
- `binutils` is one native output owning the assembler, linker, and binary
  inspection tools. It deliberately does not reproduce conda-forge's `ld_impl` /
  `binutils_impl` split.
- `make` is a native build tool, not a compiler runtime component.
- `gnuconfig` is a noarch carrier for pinned `config.guess` and `config.sub`.
- `sysroot_linux-64` is a build-time deployment baseline, not a default runtime
  sysroot for interactive compiler use.

Content-bearing packages use the normal `h<variant-hash>_<build-number>` build
string form. Metadata-only interface packages add a `meta_` prefix.

## Compiler modes

### Host-integrating default

By default, installed `gcc` and `g++` behave like newer distribution-provided
compilers. They do not embed a conda sysroot and can compile against the host's
native glibc, kernel headers, `/usr/local`, and user-installed libraries.

### Explicit channel-build mode

Recipes building channel packages explicitly select the local sysroot and tools.
There is no `gcc-buildenv` wrapper package. A recipe sets flags such as:

```bash
SYSROOT="${BUILD_PREFIX}/${sysroot_triplet}/sysroot"

export CFLAGS="--sysroot=${SYSROOT}"
export CXXFLAGS="--sysroot=${SYSROOT}"
export CPPFLAGS="--sysroot=${SYSROOT}"
export LDFLAGS="--sysroot=${SYSROOT}"
```

It must also put the intended assembler and linker ahead of host tools in `PATH`
or pass an equivalent GCC `-B` prefix.

C library headers and linker inputs are then added only through package-specific
pkg-config output or exact paths such as `${PREFIX}/include/<library>-<version>`
and `${PREFIX}/lib/lib<library>.so`. The shared `${PREFIX}/include` and
`${PREFIX}/lib` directories are not search interfaces for ordinary C libraries.

`sysroot_linux-64` is therefore not a direct runtime dependency of
`gcc-toolchain`, `gcc`, `gxx`, or `binutils`.

## Known gaps before stable promotion

- Design and add `osx-arm64` builds; the compiler and SDK strategy is pending.
- Reject recipe deletion and rename explicitly and design their release
  semantics.
- Extend graph rendering to handle mutually new local dependencies, multiple
  platforms, and reviewed output/version selection.
- Add publishable version/build-number validation and release promotion.
- Add release manifests and promotion scripts.
- Decide whether `tzdata` remains an imported data-only exception or becomes a
  local package.
- Replace current Rocky Linux mirror URLs with immutable vault URLs if archive
  stability requires it.
- Pin Pixi in CI and run the workflow in locked mode.
- Finish the GCC libstdc++ runtime strategy for hosts with older system
  runtimes.
- Define and test the oldest supported host glibc baseline.

## Bootstrap-stage command reference

The canonical workflow is `pixi run bootstrap`. The following commands are
useful when intentionally reproducing one stage manually. They must preserve the
same channel boundaries and publish/index each output before dependent recipes
are solved.

### Dirty stage

Use the seed-compatible variant:

```text
--variant-config ./variants/dirty.yaml
```

Build the GCC carrier:

```bash
rattler-build build \
  --recipe ./recipes/gcc-toolchain/recipe.yaml \
  --target-platform linux-64 \
  --channel ./channels/seed \
  --channel-priority strict \
  --variant-config ./variants/dirty.yaml \
  --output-dir ./output/dirty-toolchain
```

Publish it into `channels/dirty`, then build the `gcc` and `gxx` interfaces:

```bash
rattler-build build \
  --recipe ./recipes/gcc-aliases/recipe.yaml \
  --target-platform linux-64 \
  --channel ./channels/dirty \
  --channel ./channels/seed \
  --channel-priority strict \
  --output-dir ./output/dirty-aliases
```

After publishing those outputs, build binutils, gnuconfig, and Make against the
dirty interfaces:

```bash
rattler-build build \
  --recipe ./recipes/binutils/recipe.yaml \
  --target-platform linux-64 \
  --channel ./channels/dirty \
  --channel ./channels/seed \
  --channel-priority strict \
  --variant-config ./variants/dirty.yaml \
  --output-dir ./output/dirty-binutils

rattler-build build \
  --recipe ./recipes/gnuconfig/recipe.yaml \
  --target-platform linux-64 \
  --output-dir ./output/dirty-gnuconfig

rattler-build build \
  --recipe ./recipes/make/recipe.yaml \
  --target-platform linux-64 \
  --channel ./channels/dirty \
  --channel ./channels/seed \
  --channel-priority strict \
  --variant-config ./variants/dirty.yaml \
  --output-dir ./output/dirty-make
```

Publish each output into `channels/dirty` and regenerate its `linux-64` and
`noarch` indexes before moving to the result stage.

### Result stage

The result channel must contain the imported seed `tzdata` archive before the
first result solve, because `sysroot_linux-64` declares it as a runtime
dependency and the result stage cannot fall back to the seed channel. Copy the
single verified `channels/seed/noarch/tzdata-*.conda` archive into
`channels/result/noarch/` and index that platform before building the sysroot.
`scripts/bootstrap.sh` performs this explicit data-only import.

Then build and publish `sysroot_linux-64`:

```bash
rattler-build build \
  --recipe ./recipes/sysroot/recipe.yaml \
  --target-platform linux-64 \
  --channel ./channels/result \
  --channel-priority strict \
  --variant-config ./variants/result.yaml \
  --output-dir ./output/result-sysroot
```

Result-stage solves use `channels/dirty` for bootstrap interfaces and
`channels/result` for already-built result outputs. They must not include
`channels/seed`; a missing result dependency is an error rather than an
invitation to fall back to the seed.

All result-stage hermetic recipes use:

```text
--variant-config ./variants/result.yaml
```

Build the carrier and interface packages in this order:

```bash
rattler-build build \
  --recipe ./recipes/gcc-toolchain/recipe.yaml \
  --target-platform linux-64 \
  --channel ./channels/dirty \
  --channel ./channels/result \
  --channel-priority strict \
  --variant-config ./variants/result.yaml \
  --output-dir ./output/result-toolchain

rattler-build build \
  --recipe ./recipes/gcc-aliases/recipe.yaml \
  --target-platform linux-64 \
  --channel ./channels/result \
  --channel ./channels/dirty \
  --channel-priority strict \
  --output-dir ./output/result-aliases

rattler-build build \
  --recipe ./recipes/binutils/recipe.yaml \
  --target-platform linux-64 \
  --channel ./channels/result \
  --channel ./channels/dirty \
  --channel-priority strict \
  --variant-config ./variants/result.yaml \
  --output-dir ./output/result-binutils

rattler-build build \
  --recipe ./recipes/gnuconfig/recipe.yaml \
  --target-platform linux-64 \
  --output-dir ./output/result-gnuconfig

rattler-build build \
  --recipe ./recipes/make/recipe.yaml \
  --target-platform linux-64 \
  --channel ./channels/result \
  --channel ./channels/dirty \
  --channel-priority strict \
  --variant-config ./variants/result.yaml \
  --output-dir ./output/result-make
```

Publish and index each output immediately after it is built. Finally, rerun all
result recipes with `channels/result` as the only dependency channel into fresh
`./output/result-selfhost/` directories and publish those artifacts. This is the
fixed-point verification performed by `pixi run bootstrap`.
