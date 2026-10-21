# Language tools without Node.js

These ordinary recipes add Linux x86_64 language servers, formatters, Pandoc,
and the GHCup manager. They do not change the seed or bootstrap membership.
Node.js, bash-language-server, yaml-language-server, Pyright and prettierd are
intentionally deferred. No LaTeX distribution is included.

| Package                 | Version | Build and runtime model                                                                |
| ----------------------- | ------- | -------------------------------------------------------------------------------------- |
| `efm-langserver`        | 0.0.57  | Source-built with channel Go; no Go runtime dependency                                 |
| `shfmt`                 | 3.14.1  | Source-built with channel Go; also provides `gosh` and a man page                      |
| `lua-language-server`   | 3.19.2  | Source-built with channel Clang/libc++; embedded upstream Lua 5.5 and native modules   |
| `tinymist`              | 0.15.10 | Source-built with locked Rust and channel OpenSSL; upstream default features           |
| `typstyle`              | 0.15.2  | Source-built with locked Rust; shell completions                                       |
| `black`                 | 26.10.1 | Pure-Python wheel and locked dependencies in a private uv environment                  |
| `cmake-language-server` | 0.1.11  | Private Python environment with PyGLS 1.3.1; channel CMake and cmake-format at runtime |
| `cmake-format`          | 0.6.13  | Private `cmakelang` environment, including YAML and HTML annotation dependencies       |
| `shellcheck`            | 0.11.0  | SHA-256-pinned upstream static Linux executable                                        |
| `pandoc`                | 3.12.1  | SHA-256-pinned upstream static Linux executable and manual pages                       |
| `ghcup`                 | 0.2.6.2 | SHA-256-pinned upstream static Linux manager; no preinstalled Haskell toolchain        |

## Source builds and dependency boundaries

Go applications use Go 1.27.1, upstream go.mod/go.sum, `CGO_ENABLED=0`, trimmed
paths and module checksum verification. Go caches remain build-local. The shfmt
source-archive build stamps the pinned version when Go module metadata would
otherwise report `(devel)`. The canonical package is `shfmt`, replacing
conda-forge's `go-shfmt` name; both `shfmt` and the upstream `gosh` interpreter
are installed.

Rust applications retain Cargo.lock and default features, use Rust 1.98.1,
channel Clang/sysroot and thin LTO. Tinymist retains PDF/export, preview,
embedded fonts, localization and debugging features. Its published asset crate
contains the frontend resources, so packaging does not need a Node.js build. The
OpenSSL dependency is supplied by the channel rather than a vendored build.
Cargo dependencies are downloaded using the upstream lock; they are not separate
public conda packages.

LuaLS's release submodules archive pins its embedded Lua, bee.lua, luamake,
lpeglabel, formatter and API metadata. It does not use Neovim's LuaJIT or the
channel's regular LPeg module. The build adapts luamake's hardcoded GNU linkage
to Clang/libc++, and installs all Lua runtime scripts, metadata and locales
under `lib/devkit/libexec/lua-language-server`. The installed executable has a
relative RUNPATH selecting channel libraries; it must not load GNU libstdc++.

EFM is a protocol adapter for user-configured external commands. Installing it
does not install every formatter or linter its configuration might reference.

## Python isolation

The three Python tools use the channel's exact CPython 3.14.8 and uv 0.12.22 at
build time. `uv tool install` downloads tools and dependencies directly from
PyPI into private environments. Recipe-local `requirements.lock` files pin
versions and SHA-256 hashes rather than listing every dependency wheel in the
recipe. Because uv 0.12.22's tool installer does not enforce requirements
hashes, `uv pip sync --require-hashes --reinstall` checks the downloads using
the same build-local cache and keeps only the locked packages. The hash lock
preserves the pure-Python Black wheel and the existing native dependency wheels.
Interpreter downloads and source builds are disabled during tool installation.
Recipe-local scripts verify the environments, retain dependency license notices
and create relative public entrypoints.

Environments live below `lib/devkit/share/devkit/python-tools/`, named after the
Python distribution (`black`, `cmake-language-server`, `cmakelang`). They are
owned by conda and isolated from users' default `uv tool` directories. Native
PyYAML and MarkupSafe wheels retain their upstream library layout and are
compatible with glibc 2.28; Black uses the pure-Python implementation.

CMake Language Server's upstream dependency declaration does not exclude PyGLS
2, but that release changes the API it uses. The lock retains PyGLS 1.3.1 and
the matching lsprotocol, as the conda-forge baseline does. The old release wheel
also caps Python below 3.14. We rebuild its pinned sdist with pdm-backend 2.5.0,
locked separately in `build-requirements.lock`, and widen that declaration to
include 3.14. uv downloads the build backend and runtime dependencies; only the
source requiring this patch remains in the recipe. CMake and cmake-format are
explicit runtime dependencies for workspace inspection and formatting.

The cmake-format package also exposes `cmake-lint`, `cmake-annotate`,
`cmake-genparsers` and `ctest-to`. Jinja2 and PyYAML preserve HTML annotation
and YAML configuration support. Black retains the `blackd` entrypoint, but its
optional aiohttp extra and notebook extras are not included in the base package,
matching the baseline's separation of optional packages.

## Haskell and document conversion

ShellCheck, Pandoc and GHCup reuse upstream static Linux x86_64 binaries,
matching the Linux repack model used by conda-forge for the first two. The
checked artifacts have no dynamic section, so they do not require GHC, GMP,
libstdc++ or libgcc_s at runtime. This does not claim that a GHC downloaded
later has the same dependency properties.

Pandoc includes embedded data, Lua filters and upstream manual pages; the
`pandoc-lua` and `pandoc-server` entrypoints select upstream executable modes.
The package does not depend on a PDF engine. To generate PDFs with the channel's
Typst, install `typst` and pass `--pdf-engine=typst`. Tests exercise this route.
LaTeX engines are neither installed nor selected by package configuration.

GHCup follows the rustup model: the channel packages the manager, while recipes
that compile Haskell install an exact GHC version as a build-local input. No GHC
runtime package is added. Installing GHCup runs no bootstrap script, downloads
no toolchain, edits no shell profiles and sets no activation variables.

A Haskell source-build recipe should select its version explicitly and confine
manager state to the source directory:

```sh
unset GHCUP_USE_XDG_DIRS
export GHCUP_INSTALL_BASE_PREFIX="${SRC_DIR}/.ghcup-build"
export GHCUP_SKIP_UPDATE_CHECK=1
"${BUILD_PREFIX}/bin/ghcup" install ghc "${GHC_VERSION:?}" --set
export PATH="${GHCUP_INSTALL_BASE_PREFIX}/.ghcup/bin:${PATH}"
```

On Linux GHCup appends `.ghcup` to the prefix. The selected GHC is usable
through the build-local PATH; GHC, manager state and caches are not installed
into the output package. After the recipe exits, a regular `ghcup` command
without these variables returns to its upstream `~/.ghcup` location and does not
manage the recipe's private compiler. Any defined `GHCUP_USE_XDG_DIRS` value,
including `0`, enables XDG mode and overrides `GHCUP_INSTALL_BASE_PREFIX`, so
recipes must unset it rather than set it to zero. This package's tests use a
temporary dedicated prefix and local empty metadata to check reported
directories offline.

GHCup depends on channel curl and CA certificates. A future Haskell source-build
recipe must also pin its GHC bindist and declare the actual build requirements
(e.g. Make, tar/xz, GMP, libffi and terminal libraries); the manager alone does
not supply that closure. Downloaded compiler host dependencies must be resolved
for the build environment, and the resulting application's runtime dependencies
must be checked separately. Optional GPG verification needs GnuPG. The current
ShellCheck and Pandoc recipes use upstream static executables, so neither recipe
requires a GHC build input.

## Feature baseline and validation

The comparison uses fixed conda-forge revisions linked below. Go and Rust source
builds preserve baseline build features; LuaLS retains its bundled formatter and
metadata. The Python packages retain the base functionality and entrypoints
above. License aggregation and cargo-auditable metadata differ from forge; this
comparison does not claim exhaustive behavioral equivalence.

Package tests use version or help output for the language servers, plus simple
formatting checks for formatters. Other checks exercise ShellCheck diagnostics,
Pandoc conversion and GHCup's isolated offline manager operation. Package-layout
checks validate installed files after prefix relocation. This is
ordinary-package validation against an existing channel generation, not a new
bootstrap fixed point.

The original local validation completed full rattler-build package tests for ten
recipes; Tinymist was source-built and its installed payload passed corrected
smoke tests without repeating the Rust build. All 11 ELF payloads met the glibc
2.28 baseline, and the eleven packages had no mutually overlapping payload
paths. All three revised Python recipes passed package builds and tests after
switching downloads to uv. The dependency planner selects only these eleven
ordinary recipes.

Baseline revisions inspected on 2026-10-21; package validation continued on
2026-10-22:

- [efm-langserver `1057373`](https://github.com/conda-forge/efm-langserver-feedstock/tree/10573734ee1282e0782de06b4d662be1ca14cd79/recipe).
- [go-shfmt `84bd037`](https://github.com/conda-forge/go-shfmt-feedstock/tree/84bd0372058a7f1308bcc2a1d442cfab54734093/recipe).
- [lua-language-server `3cfad44`](https://github.com/conda-forge/lua-language-server-feedstock/tree/3cfad4480c061985e8212932c1dbba3dab1c059e/recipe).
- [tinymist `453716d`](https://github.com/conda-forge/tinymist-feedstock/tree/453716d94e737968111e29d665adb91043d3d0e1/recipe).
- [typstyle `765a5a8`](https://github.com/conda-forge/typstyle-feedstock/tree/765a5a8891edd23d8d75e6cfd566a7dc4b545158/recipe).
- [black `8d422b8`](https://github.com/conda-forge/black-feedstock/tree/8d422b80fcd71a648108e08b43f50f23314928f4/recipe).
- [cmake-language-server `4d31a2f`](https://github.com/conda-forge/cmake-language-server-feedstock/tree/4d31a2f3ce64ec6b953456ce6ae1ef7b3fef16cf/recipe).
- [cmake-format `86b6402`](https://github.com/conda-forge/cmake-format-feedstock/tree/86b640266ed2c8aad80af9defc4ec8b11ee559a4/recipe).
- [shellcheck `1b50ef5`](https://github.com/conda-forge/shellcheck-feedstock/tree/1b50ef53375e5b08cfbc455febefc3e930145d51/recipe).
- [pandoc `f6f6cef`](https://github.com/conda-forge/pandoc-feedstock/tree/f6f6cef7a45bd56177d9670264371b9c1548947f/recipe).
- [ghcup `b4227c2`](https://github.com/conda-forge/ghcup-feedstock/tree/b4227c2c3cd8ac78f25826ecb4a6a96ee3fa81f0/recipe).
