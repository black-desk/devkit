# Devkit channel workspace

This repository builds an independent development-tool conda channel. Linux is
being migrated to Clang/LLVM; `osx-arm64` is planned. See
[the experiment notes](docs/clang-bootstrap.md) for validation completed on
`experiment/clang-bootstrap` and work still pending.

The project is not a conda-forge overlay. Existing and future packages use
canonical names such as `clang`, `go`, `python`, and `rustup`, and the channel
does not attempt to make its toolchain packages co-installable with
conda-forge's toolchain stack in the same environment.

## Current status

The seed-built Clang carrier, libcxx, llvm-libgcc, Ninja, Make, and pkgconf have
passed their package tests. A fresh installation containing no GCC compiler or
development packages has passed both compiler integration checks: default C++
compilation uses host GCC development files and host libstdc++, and explicit
channel builds use the Rocky sysroot, libc++, and llvm-libgcc. Full result-stage
self-hosting and ordinary-package builds remain in progress. The
[bootstrap closure inventory](docs/bootstrap-closure.md) records all seed
members, missing recipes, feature gaps and unresolved file ownership.

The intended stages are seed → dirty → result → result-only rebuild. Each
executes `bootstrap-order.json`, covering the sysroot, LLVM runtimes, Clang, GNU
config scripts, Make, Perl, pkgconf, CA certificates, OpenSSL, Ninja, and CMake.
Its library/build-tool closure now also schedules bzip2, libuv, RHash, c-ares,
libev, keyutils, libedit, zlib, zstd, ncurses, libiconv, liblzma, ICU, libpsl,
gettext (with a file-free gettext-tools alias), libxml2, Kerberos, libssh2,
libnghttp2, curl (with a file-free libcurl alias), libxcrypt, and expat (with a
file-free libexpat alias), LZO, LZ4, libarchive with LZO support, jsoncpp, and
cppdap. Validation status and the remaining dependencies are recorded in the
inventory. The result-only closure includes those outputs and imported `tzdata`;
it contains no GNU compiler, binutils, libgcc, or libstdcxx package. llvm-libgcc
provides the `libgcc_s.so.1` interface with LLVM sources.

`seed-packages.tsv` pins 47 conda-forge archives, including Clang/LLVM 23.1.3,
LLD 23.1.2, CMake, Ninja, gettext-tools 0.25.1, GNU runtime/development files,
Perl 5.44.0, libxcrypt 4.4.38, and the glibc 2.28 sysroot. There is no GCC
compiler or GNU binutils in the seed. Dirty builds prefer dirty packages and
fall back to seed in both environments. Dirty-only runtime SONAME links keep
seed tools working with private channel libraries. GNU libgcc stays in seed
public lib, while LLVM-libgcc uses the private library directory; no libgcc meta
replacement is needed. Library meta aliases retain conda-forge split-package
dependency interfaces. Rebuilding the complete tool dependency closure is
intended to make result independent of seed.

`tzdata` is an explicitly retained data-only seed exception. Its permanent
status or replacement remains a release decision.

The first ordinary toolchain input is a version-pinned repack of the official
Linux/amd64 Go distribution. Its official GOROOT layout is retained below
`lib/go/<version>/`, with `go` and `gofmt` linked from `bin/`. `lazygit` is the
first normal tool recipe; it declares the channel's `git` package as a runtime
dependency so installation includes Git on `PATH`. The canonical `rustup`
manager is also packaged as an official binary repack without a selected Rust
toolchain. The tools built from that locked Rust input currently include
`ripgrep`, `fd`, `uv`, `yazi`, and `just`. macOS builds and a release promotion
process are still incomplete. The Linux package workflow has an initial
affected-build scheduler for the current bootstrap recipes and these ordinary
packages.

`difftastic` is also built from the locked Rust toolchain input.

The [additional channel tools](docs/channel-tools.md) are GitHub CLI `gh`
2.102.1, dotfile manager `chezmoi` 2.73.3, Typst 0.15.1, and the Neovim Python
client/provider `pynvim` 0.6.0. The Go applications and Typst build from pinned
source with completions; Typst retains embedded fonts and channel OpenSSL.
Pynvim exposes `pynvim-python` from a private Python environment, with its
greenlet and MessagePack extensions built against the channel C/C++ toolchain.
These ordinary recipes do not change the seed or bootstrap membership.

The `yazi` recipe builds Yazi 26.9.1 and its `ya` companion with embedded Lua,
Bash/Fish/Zsh completions, and the glibc 2.28 sysroot. Git, fd, and ripgrep are
runtime dependencies for plugin management and search. Additional preview and
opener tools remain optional: `file`, FFmpeg, 7-Zip, Poppler (`pdftoppm`),
ImageMagick, `fzf`, `zoxide`, and `xdg-open` must be supplied separately for the
features that use them. The terminal test starts Yazi in a pseudoterminal,
checks a file listing, sends a quit action through `ya`, and verifies the saved
working directory.

The `just` recipe builds just 1.58.0 with Bash/Fish/Zsh completions and a man
page. Its tests exercise recipe dependencies, parameters, and dry runs. Both
Rust recipes retain upstream Cargo.lock, use Rust 1.98.1 and the channel C
toolchain/sysroot for native dependencies, and use thin LTO to limit build
memory.

The `gopls` recipe builds gopls 0.23.0 using Go 1.27.1, upstream go.mod/go.sum,
module checksum verification, `CGO_ENABLED=0`, and trimmed build paths. Unlike
standalone Go applications, the language server needs the Go command at runtime
to load workspaces; it depends on the channel's Go 1.27 series. Offline tests
check symbol definitions and diagnostics in a local module. Build and test
telemetry is disabled, without changing user telemetry settings.

The ordinary [Clang tools recipe](docs/clang-tools.md) provides `clangd` and
`clang-tidy` 23.1.3, including clangd's integrated linter and clang-tidy's
automatic-fix helpers. Both depend on the matching channel Clang for shared
libraries and resource headers. Their shared staging build does not change the
seed, bootstrap membership or compiler recipe. Installed tests exercise LSP
definitions/diagnostics, static analysis and automatic fixes.

The `uv` recipe builds uv 0.12.22 and its `uvx` launcher from source, with Bash,
Fish, and Zsh completions. It uses the locked Rust toolchain and local
Clang/LLVM/Make/sysroot for its native dependencies. The release build keeps the
upstream performance allocator, uses thin LTO to reduce build memory, and
disables self-update so upgrades remain owned by the channel. The package does
not include a Python interpreter. Its offline package tests cover both
executables, custom installation directories, project initialization, and the
bundled Python download metadata. The migrated Linux builds select host glibc
and channel llvm-libgcc through RUNPATH; their complete rebuild and runtime
audit remain pending.

The `python` recipe packages CPython 3.14.8 from the `python-build-standalone`
20261001 release. Rattler-Build verifies the pinned archive, then uv 0.12.22
installs it from a local mirror without network access. The distribution stays
under `lib/uv-python/`, with `python`, `python3`, and `python3.14` exposed in
`bin/`. It retains the bundled standard library, headers, shared Python library,
and pip; uv is a build dependency only. Package tests check relocated
interpreter and sysconfig paths, native standard library modules, virtual
environments with pip, and offline uv tool installation.

The `b4` recipe packages b4 0.16.0 as the first private Python tool environment.
It installs offline with uv 0.12.22 under
`lib/devkit/share/devkit/python-tools/b4`, with a relative `bin/b4` symlink and
exact Python 3.14.8 runtime dependency. Git is also a runtime dependency. All 15
runtime distributions and the setuptools 84.0.0 build backend are pinned;
Rattler-Build verifies each input's SHA-256 before uv runs. Only dkimpy 1.1.8
comes from an sdist: setuptools packages its Python files without a native
compiler. Other inputs use upstream wheels, including the native pygit2, PyNaCl,
CFFI, and charset-normalizer extensions. Their bundled libraries and relative
RPATHs are retained, with a glibc 2.28 minimum. Tests cover relocated
interpreter/receipt paths, dependency versions, native Git and signing
operations, isolation from normal uv tool management, and an offline
`git format-patch` → `b4 am` → `git am` workflow. Optional completion/TUI
extras, OpenPGP via GnuPG, and git-bug integration are not included.

The [Neovim recipe](docs/neovim.md) builds Neovim 0.12.6 as `neovim`, with
`nvim` on PATH, LuaJIT, Tree-sitter and all upstream default parsers, runtime
files, help, man page and translations. Its libraries and parsers use
independent channel recipes, with shared LuaJIT, luv, LPeg, unibilium, utf8proc
and Tree-sitter alongside the existing libuv and libiconv packages.

The language tools add EFM, LuaLS, CMake Language Server, Tinymist, Black,
cmake-format, shfmt, ShellCheck and typstyle, plus Pandoc and the GHCup Haskell
toolchain manager. Node.js-based tools are deferred. Pandoc PDF tests use Typst;
no LaTeX distribution is included. GHCup follows the rustup model: Haskell
source builds can use a private compiler via build-local
`GHCUP_INSTALL_BASE_PREFIX` and PATH settings; no GHC package or activation
variables are installed.

The [mail tools](docs/mail-tools.md) recipes add notmuch 0.39, aerc 0.22.0 with
its notmuch backend, lei from public-inbox 2.0.0, and lieer 1.6 (`gmi`). Their
ordinary dependency closure includes GLib, GMime, Xapian, talloc and GPGME;
Python and Perl modules are isolated in private tool environments. The seed
manifest is unchanged. See the mail-tools document for installation scope,
external GnuPG requirements and offline functional tests.

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

Recipe feature configuration uses conda-forge as the baseline. Preserve features
that conda-forge enables wherever possible; reducing the bootstrap dependency
count is not sufficient reason to disable them. Compare the actual upstream and
conda-forge build configurations before claiming feature parity. Any necessary
feature reduction must document its user-visible impact and be discussed with
the maintainer before implementation.

The [ordinary recipe feature audit](docs/ordinary-feature-audit.md) compares the
post-bootstrap recipes against fixed conda-forge revisions. It records confirmed
PCRE2, ripgrep, Git and B4 gaps, external-tool dependency differences, and
settings that need targeted validation. The prebuilt Python and Rust
distributions are excluded at the maintainer's request. Passing existing smoke
tests does not establish full feature parity.

The bootstrap is a self-hosting closure, including seed tools' runtime
dependencies as well as their build dependencies. Reconstruct those dependencies
from channel sources, or replace the corresponding tool with a verified
implementation/configuration that no longer needs them. An ordered list of tool
recipes alone does not establish closure. Validate a complete seed-free rebuild,
including all required libraries. The current bootstrap membership is
provisional pending this dependency and feature audit.

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
retired-packages.json    Explicitly retired package outputs

recipes/
  clang/                Clang, LLVM tools, LLD, compiler-rt, build helpers
  clang-tools/          Ordinary clangd and clang-tidy with shared staging
  libcxx/               libc++ and libc++abi, with isolated headers
  llvm-libgcc/          LLVM unwinder and compiler-rt runtime interfaces
  cmake/                CMake/ccmake using external channel libraries
  ninja/                Ninja build executor
  bzip2/                Bzip2 compression library and tools
  c-ares/               Asynchronous DNS resolver
  cppdap/               Debug Adapter Protocol library using jsoncpp
  gettext/              Gettext libraries/tools and gettext-tools meta alias
  icu/                  ICU with release-provided data
  jsoncpp/              C++ JSON reader/writer
  keyutils/             Linux kernel keyring API
  krb5/                 MIT Kerberos with NLS
  libarchive/           Archive library/tools with LZO and LZ4 support
  libedit/              Command-line editing library
  libev/                Event-loop library
  libiconv/             Character-set conversion library
  liblzma/              XZ compression library and tools
  libnghttp2/           HTTP/2 library and tools
  libpsl/               Public suffix list library
  libssh2/              SSH/SCP/SFTP client library
  libuv/                Portable asynchronous I/O
  libxml2/              XML library and libxml2-16 meta alias
  lz4-c/                LZ4 library and CLI
  lzo/                  LZO compression library
  ncurses/              Narrow/wide ncurses and split tinfo/form
  rhash/                Hashing library and CLI
  zstd/                 Zstandard library, CLI and pzstd
  ca-certificates/      Pinned Mozilla CA certificate bundle
  expat/                Stream-oriented XML parser library
  make/                 GNU Make carrier
  git/                  Git with Rust, HTTPS, PCRE2, Perl scripts, and subtree
  gnuconfig/            Pinned config.guess and config.sub
  openssl/              TLS and cryptography library
  pcre2/                Perl-compatible regular expression library
  libxcrypt/            Password hashing library used by Perl
  perl/                 Perl interpreter and core modules
  sysroot/              Rocky Linux 8.10-derived Linux sysroot
  go/                    Official Go linux-amd64 distribution repack
  lazygit/               Terminal UI for Git commands
  gopls/                 Go language server
  efm-langserver/        General-purpose external-tool language server
  shfmt/                 Shell formatter and gosh interpreter
  lua-language-server/   LuaLS with embedded Lua and channel libc++
  tinymist/              Typst language service, preview and export
  typstyle/              Typst source formatter
  black/                 Python formatter in a private environment
  cmake-language-server/ CMake language server in a private environment
  cmake-format/          CMake formatting, linting and annotation tools
  shellcheck/            Upstream static shell analyzer
  pandoc/                Upstream static document converter
  ghcup/                 Upstream static Haskell toolchain manager
  gh/                    GitHub CLI with completions and manual pages
  chezmoi/               Dotfile manager with shell completions
  typst/                 Typesetting CLI with embedded fonts and OpenSSL
  yazi/                  Terminal file manager and ya companion
  just/                  Project command runner
  fd/                    Fast filesystem search tool
  ripgrep/               Fast regex search tool
  difftastic/            Syntax-aware structural diff tool
  pkgconf/               pkg-config-compatible metadata query tool
  rustup/                Official Rust toolchain manager binary repack
  b4/                    Mailing-list patch tools in a private uv environment
  neovim/                Text editor using channel LuaJIT and Tree-sitter
  pynvim/                Neovim Python client/provider in a private environment
  luajit/                LuaJIT interpreter, shared library and JIT modules
  lua-lpeg/              LPeg shared library and Lua module
  luv/                   Shared libuv Lua bindings and Lua module
  lua-compat-5.3/        Lua compatibility headers used to build luv
  unibilium/             Terminfo parsing library
  libutf8proc/           Unicode processing library
  libtree-sitter/        Incremental parser runtime
  tree-sitter-c/         C parser module
  tree-sitter-lua/       Lua parser module
  tree-sitter-vim/       Vim parser module
  tree-sitter-vimdoc/    Vimdoc parser module
  tree-sitter-query/     Query parser module
  tree-sitter-markdown/  Markdown and inline Markdown parser modules
  notmuch/               Mail indexer and shared C API
  aerc/                  Terminal mail client with the notmuch backend
  lei/                   Local email interface with private CPAN dependencies
  lieer/                 Gmail/notmuch synchronization in a private uv environment
  libffi/                Foreign function interface library
  glib/                  GLib, GObject and GIO libraries
  talloc/                Hierarchical allocator
  xapian/                Full-text search engine
  libgpg-error/          GnuPG error/runtime library
  libassuan/             GnuPG IPC library
  gpgme/                 GnuPG engine interface
  gmime/                 MIME parser and message library
  scdoc/                 Manual generator for aerc
  python/                CPython standalone distribution installed by uv
  uv/                    Python package, tool, and interpreter manager
  zlib/                  General-purpose compression library

variants/
  dirty.yaml            Seed-compatible bootstrap variant
  result.yaml           Result sysroot and target-triplet variant

scripts/
  bootstrap.sh          Run all bootstrap stages or a single stage
  clean-build-outputs.py Preserve source caches while removing generated output
  affected-plan.sh      Validate revisions and write a portable build plan
  affected-build.sh     Run the planned local pipeline
  build-ordinary.sh     Build ordinary recipes from an existing plan
  channel-artifact.py   Verify, seal and merge portable stage channels
  bootstrap-fingerprint.py Hash complete bootstrap inputs for CI cache reuse
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
frequently ambiguous—`clang` is both a bootstrap artifact and the public
compiler interface, while `python` is both a language runtime and a build
input—and they must not become inputs to build scheduling.

The intended layout is:

```text
recipes/
  aerc/
  clang/
  cmake/
  ca-certificates/
  difftastic/
  expat/
  fd/
  libcxx/
  llvm-libgcc/
  ninja/
  git/
  gnuconfig/
  go/
  lazygit/
  make/
  neovim/
  notmuch/
  openssl/
  pcre2/
  libxcrypt/
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
`recipes/python/` produces `python`. The seed compiler names are used only by
dirty-stage conditional build requirements; they do not become result outputs.

For ordinary packages, the build graph is derived from rendered recipes. Each
package output is a graph node, so a multi-output recipe contributes its actual
output names rather than a directory name. Direct dependency specifications form
the edges; a complete resolved closure is not expanded into direct edges.

Bootstrap membership is explicit rather than inferred from a directory. It is
represented by `bootstrap-order.json`, a top-level JSON array of recipe
directory names. `scripts/bootstrap.sh` executes that order in each stage; the
dependency-graph tool reads the same array as the bootstrap generation
membership. Stage-specific variants and channel boundaries remain part of the
bootstrap and graph entry points rather than the recipe namespace.

The bootstrap recipes are special. Collapsing their staged package names can
produce cycles between Clang, LLVM runtimes, CMake, and Ninja. They are
therefore handled as a bootstrap generation supernode rather than fed directly
to the ordinary topological scheduler. Outside bootstrap, SCCs should be
rejected.

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

macOS, release manifests, promotion, and the future mail toolchain remain later
work. A completed seed build does not establish a verified self-hosting fixed
point.

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

The Go distribution, rustup manager, Rust toolchain lock, Python, and uv recipes
are current. Their detailed consumer policies and the remaining language-runtime
recipes below are target design unless a current recipe says otherwise.

External language toolchains are exact inputs to CI builds. Finished native
tools do not depend on their compiler manager at runtime unless their own
functionality requires it, as gopls requires the Go command for workspace
analysis.

### Rust

The channel packages `rustup` normally, but does not package generic `rustc` or
`cargo` outputs as though they were the selected toolchain.

A separate `rust-toolchain-lock` package records the exact selected Rust
toolchain. It is currently pinned to Rust `1.98.1`. Rust-using recipes declare
these packages as build dependencies and install that exact toolchain into
build-local state:

```bash
export CC="${BUILD_PREFIX}/bin/clang"
export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="${CC}"
export RUSTFLAGS="-C link-arg=--no-default-config -C link-arg=--config=${BUILD_PREFIX}/lib/devkit/share/devkit/clang.cfg -C link-arg=-L${PREFIX}/lib/devkit/lib -C link-arg=-Wl,-rpath-link,${PREFIX}/lib/devkit/lib -C link-arg=-Wl,-rpath,${PREFIX}/lib/devkit/lib"
devkit_rustup() {
  env -u LD_LIBRARY_PATH LD_PRELOAD="${BUILD_PREFIX}/lib/devkit/lib/libgcc_s.so.1" \
    "${BUILD_PREFIX}/bin/rustup" "$@"
}

export RUSTUP_HOME="${SRC_DIR}/.rustup"
export CARGO_HOME="${SRC_DIR}/.cargo"
export CARGO_TARGET_DIR="${SRC_DIR}/target"

RUST_TOOLCHAIN="$(cat "${BUILD_PREFIX}/share/rust-toolchain/version")"

devkit_rustup toolchain install "${RUST_TOOLCHAIN}" \
  --profile minimal \
  --no-self-update

export RUSTC="$(devkit_rustup which --toolchain "${RUST_TOOLCHAIN}" rustc)"
export RUSTDOC="$(devkit_rustup which --toolchain "${RUST_TOOLCHAIN}" rustdoc)"

devkit_rustup run "${RUST_TOOLCHAIN}" cargo build \
  --release \
  --locked
```

Each Rust recipe defines its own local `devkit_rustup` function. It clears
`LD_LIBRARY_PATH` and sets an absolute `LD_PRELOAD` for channel `libgcc_s.so.1`
only while running upstream Rust tools during a Rust recipe build. Their
subprocesses receive this scoped environment. Installed outputs and independent
package tests use DT_RUNPATH without loader overrides. Packaged rustup has its
own RUNPATH; user-downloaded toolchains retain upstream host requirements.

Toolchain requests must be exact. Ambiguous requests such as `stable`,
`nightly`, or a minor version without a patch are not accepted. Changing the
lock package triggers rebuilding the reverse build-dependency closure.

### Go

The `go` package is a version-pinned repack of the official Go distribution for
each supported platform. The complete official GOROOT is installed below
`lib/go/<version>/`, while `bin/go` and `bin/gofmt` are relative links into it.
Standalone Go applications use it as a build dependency only; gopls also
declares a Go runtime dependency.

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
toolchain nor its module/build caches become runtime dependencies of standalone
applications. The gopls exception includes the Go toolchain but no build caches.

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

Python tool recipes use `uv tool install` to create private environments below
the package prefix, with exact per-platform constraints for the tool and all
transitive dependencies. `recipes/b4/` implements this for Linux x86_64, using
SHA-256-pinned local artifacts and a pinned build backend. When updating b4,
update `requirements.lock`, `build-constraints.txt`, and the corresponding
URLs/hashes in `recipe.yaml` together. Native wheel tags must remain compatible
with the packaged Python and the glibc 2.28 floor. The build-local configuration
follows this pattern:

```bash
export UV_CACHE_DIR="${SRC_DIR}/.uv-cache"
export UV_NO_CONFIG=1
export UV_PYTHON_DOWNLOADS=never
export UV_TOOL_DIR="${PREFIX}/lib/devkit/share/devkit/python-tools"
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
${PREFIX}/lib/devkit/include/foo-1.2.3/
```

It must not install public headers directly below
`${PREFIX}/lib/devkit/include`. That rule is intentional: a broad
`-I${PREFIX}/include` must never make channel headers for an unrelated library
visible while building against another package. Consumers use the exact root
selected by the library's pkg-config entry:

```bash
CFLAGS="$(pkg-config --cflags foo)"
```

or an explicit equivalent:

```bash
-I${PREFIX}/lib/devkit/include/foo-1.2.3
```

Recipes therefore do not add a generic `-I${PREFIX}/include` to `CPPFLAGS` or
`CFLAGS`. When upstream's Makefile, CMake package, or pkg-config metadata
assumes a shared include directory, the recipe overrides the install path or
patches that metadata. In particular:

- pkg-config `Cflags` must point at the version-specific include root.
- Preserve upstream-generated `Libs`, `Libs.private`, `Requires` and
  `Requires.private`. Native `-L${libdir} -lfoo` output is supported; libdir
  points into the private installation directory.
- pkg-config `Requires` and `Requires.private` must preserve transitive public
  header dependencies.
- exported CMake include paths and imported-target interface directories must
  use the same root; an upstream config that cannot be corrected is not
  installed.
- upstream `foo-config` helpers are corrected rather than deleted, but they are
  package-private build metadata programs rather than user commands.
- tests must compile and run a small consumer without adding the shared
  `${PREFIX}/lib/devkit/include` directory to the compiler command line.

Package metadata tests use the channel-owned `pkgconf` package through its
`pkg-config` compatibility name; they do not rely on a `pkg-config` executable
from the build host or the Pixi orchestration environment.

Corrected `foo-config` helpers install below:

```text
${PREFIX}/lib/devkit/libexec/<package>/bin/
```

They must not install into `${PREFIX}/bin`. Use native directory options where
available, with recipe-local installation adjustments where needed. Preserve the
upstream command-line interface and generated dependency lists. Query output
names the private library directory and versioned include roots.

Downstream recipes do not put these helpers on the public `PATH`. A recipe that
cannot use pkg-config refers to the helper directly—for example,
`${PREFIX}/lib/devkit/libexec/pcre2/bin/pcre2-config`—or prepends only that
package's private helper directory inside its own build script. Activation
scripts must not expose these directories globally.

Shared objects, archives and their development links install together under
`${PREFIX}/lib/devkit/lib`, preserving upstream SONAMEs. Only dirty provides
public SONAME compatibility aliases for seed tools. C library recipes also
declare appropriate ABI `run_exports`, and downstream recipes use direct
dependency specifications rather than expanding a solved closure into their
metadata.

Target-package rendering and builds use only the pull request's local
`channels/result` overlay and `https://prefix.dev/black-desk`. Conda-forge is
not a fallback for target dependencies. The hosted channel must not declare a
CEP 42 base or override relation, because rattler-build discovers and follows
those relations recursively; the affected-build script checks its repodata
before building. The locked Pixi environment that runs the build scripts is a
separate orchestration layer and may still use external tools until equivalent
channel-owned build tooling exists.

The compiler's internal headers and `sysroot_linux-64` are exceptions to this
layout: they implement the compiler/sysroot interface rather than ordinary
channel libraries.

All configurable directories apart from public `bin` use `lib/devkit`, including
runtime libraries and modules. CMake modules remain in public `share/cmake-3.31`
so CMake does not infer the private prefix as a default package search path.
Imported sysroot and language-runtime internal layouts are deliberate
exceptions. See [the development layout policy](docs/development-layout.md).

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
under a recipe directory initially selects all outputs of that recipe. Changes
to explicit global bootstrap inputs select every recipe; workflow and
documentation changes do not schedule package builds. Refinement to individual
outputs can be added only when the mapping is explicit and auditable. The
completed-stage test runner and shared build-output cleanup helper are global
bootstrap inputs as well.

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

## Package roles in the current bootstrap

- `clang` owns Clang, LLVM tools, LLD, and the explicit channel build helpers.
  Compilation uses the runner's full CPU count; at most two LLVM links run
  concurrently.
- `libcxx` owns libc++ and libc++abi, including version-isolated headers.
- `llvm-libgcc` owns compiler-rt builtins, CRT objects, and the LLVM unwinder.
  Its canonical SONAME is `libgcc_s.so.1`; libunwind aliases select that ELF.
- `make`, `perl`, `pkgconf`, `openssl`, `ca-certificates`, `ninja`, and `cmake`
  complete the build-tool closure.
- `libxcrypt` provides Perl password hashing. Each stage uses the previous
  generation's Perl to build libxcrypt, then builds its own Perl against the
  library supplied by that stage's dependency channels. Seed includes both
  packages to start this cycle.
- `gnuconfig` owns pinned platform-detection scripts.
- `sysroot_linux-64` supplies the glibc 2.28 build baseline. It is not a runtime
  dependency of the public compiler.

`retired-packages.json` records the removed GCC, G++, GNU binutils, and
libstdcxx package outputs. The planner permits these deliberate removals and
still rejects unlisted output deletion or rename.

## Package splits and compatibility names

Content-bearing packages own complete upstream installations; we do not
reproduce conda-forge's file splits solely to match package names. Where a seed
or consumer requires a split name, provide a metadata-only compatibility package
that depends on the matching content-bearing package. Compatibility packages own
no library or header files and must not cause file collisions. Content-bearing
build strings use `h<variant-hash>_<build-number>`; metadata-only interfaces use
the `meta_` prefix. The temporary dirty-stage `libgcc` interface is an explicit
exception: its version and build string match seed libstdcxx’s exact dependency,
while its only runtime dependency is our LLVM-libgcc. It owns no files and is
omitted from result/self-host outputs.

For example, `zlib` owns the shared/static libraries and version-isolated
headers. `libzlib` is a noarch metadata-only output of the same recipe, with an
exact dependency on its sibling `zlib` output. This satisfies seed CMake's
`libzlib` dependency without installing conda-forge's split runtime package.

## Compiler modes

### Host-integrating default

`bin/clang.cfg` and `bin/clang++.cfg` select `--gcc-toolchain=/usr`. Normal
compiler invocations use host GCC's matching C++ headers, libstdc++, and libgcc,
plus the host linker. The compiler itself uses channel libc++ and llvm-libgcc;
that is independent of the runtime selected for its outputs.

### Explicit channel-build mode

Channel recipes load `lib/devkit/share/devkit/clang.cfg` with
`--no-default-config`. It selects the Rocky sysroot, LLD, libc++, compiler-rt,
and the LLVM unwinder. LLD is selected by its explicit `--ld-path`, avoiding
Clang's deprecated absolute-path `-fuse-ld` form and failures in configure
probes using `-Werror`. `<CFGDIR>`-relative paths make the configuration
relocatable. Native recipes declare their compiler, LLVM tool paths and build
flags directly in each recipe's build script. No build/test/Rust environment
scripts are installed by the compiler package. Bootstrap recipes select the
stage's compiler policy and sysroot variant. When preparing each fresh seed
build environment, the recipe creates relative `clang` and `clang++` symlinks to
the seed's `clang-23` and `clang++-23` commands, so every stage uses the same
driver names. These links exist only in the temporary build prefix; seed
archives and the seed manifest remain unchanged. Seed builds explicitly select
target libc++ headers. Later native stages use the config's single libc++ header
root to avoid duplicate C wrappers breaking include_next; both prefixes select
the same libc++ package from the completed input channel.

Public C library headers remain version-isolated. Ordinary library interfaces
are passed through exact pkg-config output or exact header/library paths. The
runtime directory used by the compiler is a deliberate standard-library
interface, not a generic header search path.

Channel CMake uses upstream discovery rules. Channel development files are
hidden under `lib/devkit`, outside the ordinary installation prefix search
locations. Recipes explicitly set CMAKE_PREFIX_PATH and PKG_CONFIG_LIBDIR to
that development prefix. Versioned include paths still need upstream CONFIG
metadata, pkg-config or explicit Find-module variables. Channel pkgconf defaults
to host metadata directories. See
[the layout policy](docs/development-layout.md).

### Runtime policy

Build systems write relative installed DT_RUNPATH natively wherever supported:
CMake handles build/install paths separately, Cargo uses linker arguments, Meson
links pkgconf with its installed tool path, and ordinary Make projects receive
escaped linker flags. Build/test binaries search public runtime libraries rather
than hidden development aliases. `finalize-elf.py` remains for explicitly
annotated Libtool/mixed-depth install exceptions and repacked upstream binaries.
It preserves input dependency files and installed permissions. Recipes disable
Rattler-Build's automatic binary relinking because it converts RUNPATH to RPATH.
Text and symlink relocation remain enabled.

Ordinary builds and package tests do not use loader overrides. Only upstream
Rust tool invocations in Rust recipe builds receive scoped preload. RUNPATH is a
search policy, not hard host-library isolation: glibc remains supplied by the
host, and strict loader isolation is deferred.

llvm-libgcc is an LLVM implementation of the libgcc interface, not a guarantee
of every GNU runtime symbol/version. Controlled channel dependencies and their
runtime tests must validate the required interface.

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

Bootstrap stage boundaries: dirty build and host environments prefer already
built dirty packages and fall back to seed. Result uses completed dirty only;
self-hosting uses completed result only. Both local and CI bootstrap skip
upstream suites and independent package tests in dirty and result. Final
self-hosting runs upstream suites during builds, then
`scripts/test-bootstrap-stage.sh` executes the packaged recipe tests using only
the completed stage channel. Channel-wide closure/compiler/runtime/glibc checks
run at dirty/result boundaries and in the final smoke job; selfhost checks
closure before handing off its output. Package builds use `--test skip` to defer
independent package tests until the full stage is available. Self-hosting reads
the completed result and writes `channels/result-rebuild`; local full bootstrap
promotes it after all checks pass, while CI passes it read-only to ordinary
builds and assembles the publication channel later. Recipes read
`DEVKIT_RUN_TESTS` through the supported script environment interface: `0` skips
upstream suites and `1` runs them. Standalone recipe builds default to `1`; this
setting does not add a stage variant or alter package hashes. Cheap build smoke
probes remain enabled throughout. Final-stage suites retain their full
workloads, including Zstd's 30,000-round fuzzer. The generated per-stage package
manifests live inside their stage channels as `stage-packages.txt`. The expanded
closure still needs validation; this infrastructure change does not establish a
successful bootstrap. Stage checks also inspect installed ELF symbol versions
against the glibc 2.28 sysroot baseline. Autotools recipes patch bundled libtool
to retain explicit Clang configuration and linker flags during shared-library
links; otherwise libtool can silently reload the default host policy.
