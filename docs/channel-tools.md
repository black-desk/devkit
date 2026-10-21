# Additional channel tools

These ordinary Linux x86_64 recipes are discovered by the rendered dependency
graph. They add no seed archives or bootstrap members. After publication,
install with the channel selected by the client, for example:

```bash
pixi add --channel https://prefix.dev/black-desk gh pynvim typst chezmoi
```

| Package   | Version | Public command  |
| --------- | ------- | --------------- |
| `gh`      | 2.102.1 | `gh`            |
| `pynvim`  | 0.6.0   | `pynvim-python` |
| `typst`   | 0.15.1  | `typst`         |
| `chezmoi` | 2.73.3  | `chezmoi`       |

## Build and installation scope

GitHub CLI and chezmoi build with channel Go 1.27.1, upstream go.mod/go.sum,
module checksum verification, trimmed build paths and `CGO_ENABLED=0`. Go is a
build input only; Git is a runtime dependency for repository operations. Both
include Bash, Fish and Zsh completions. GitHub CLI also includes its generated
manual pages. Authentication, browser integration, password-manager helpers and
other external services retain upstream configuration requirements.

Typst uses Rust 1.98.1, upstream Cargo.lock, channel Clang 23.1.3 and the glibc
2.28 sysroot. It retains default features, including embedded fonts, the watch
HTTP server and PDF, SVG, PNG and HTML export. Package downloads use dynamic
channel OpenSSL; its normal certificate bundle remains available through the
OpenSSL runtime dependency. The optional self-update Cargo feature remains
disabled, matching upstream and conda-forge defaults. Thin LTO limits build
memory. Completions and manual pages live under `lib/devkit/share`.

Like the conda-forge package, Typst supplies Conda environment-variable metadata
for package and font discovery. The channel's paths are
`lib/devkit/share/typst/packages` and `lib/devkit/share/fonts`, recorded
relative to the environment through Conda text-prefix relocation. Activation
applies these settings; clients that do not activate environments can set
`TYPST_PACKAGE_PATH` and `TYPST_FONT_PATHS` explicitly. Embedded fonts remain
available without activation. Third-party Typst packages and extra fonts are not
bundled.

Pynvim uses the channel's exact CPython 3.14.8 in a private uv environment at
`lib/devkit/share/devkit/python-tools/pynvim`. Its upstream `pynvim-python`
command is linked into `bin`, allowing Neovim 0.12.6 to discover its provider
automatically. Install `neovim` alongside it for local editor use. Python
library consumers can run `pynvim-python -c 'import pynvim'` or use the private
environment's interpreter; the package does not add modules to the public Python
interpreter's site-packages.

All Python inputs have SHA-256 pins. Pynvim 0.6.0 comes from its pure-Python
wheel. Greenlet 3.5.6 and MessagePack 1.2.3 build offline from sdists using
setuptools 84.2.1 and channel Clang. Greenlet links channel libc++ and
llvm-libgcc rather than importing a wheel that needs GNU libstdc++. The private
environment contains only the three runtime distributions; uv and setuptools are
build inputs. Native extensions, including greenlet's nested test modules,
receive depth-specific relative RUNPATHs after uv installs the wheels. This is a
recipe-local mixed-depth installation exception; dependency files are untouched.
Dependency license notices are retained in the environment and package metadata.

## Feature baseline

Reviewed on 2026-10-21 against these fixed conda-forge recipe revisions:

- [`gh` bd0f2f4](https://github.com/conda-forge/gh-feedstock/tree/bd0f2f4e556abb8cfbaf38ffa1ea1e34739c53c5/recipe),
  version 2.102.1: both use no-cgo builds and install Bash/Fish/Zsh completions
  and manual pages. Our license metadata follows the pinned upstream MIT
  LICENSE; the baseline feedstock labels it Apache-2.0.
- [`chezmoi` e4adc32](https://github.com/conda-forge/chezmoi-feedstock/tree/e4adc323c535711117c90e578aaeb9861349c0d4/recipe),
  version 2.73.0: both use no-cgo builds without feature-removing tags and ship
  Bash/Fish/Zsh completions. Our 2.73.3 recipe also declares Git for repository
  operations.
- [`typst` 6734eaf](https://github.com/conda-forge/typst-feedstock/tree/6734eafd1cf95c9c776c3e1a900f9ad4ba53b278/recipe),
  version 0.15.1: both retain default Cargo features, dynamic OpenSSL,
  completions and environment package/font paths. Our paths follow the private
  installation policy; we additionally install upstream-generated manual pages.
  Thin versus fat LTO and the absence of cargo-auditable metadata are build
  differences.
- [`pynvim` 523c103](https://github.com/conda-forge/pynvim-feedstock/tree/523c1036b45a5dea5e20a8e6f4e1f17c83e91a3d/recipe),
  version 0.6.0: both provide the upstream Python client, provider entrypoint,
  greenlet and MessagePack. Our native dependencies are source-built inside the
  private environment instead of separate public Python packages. Upstream
  requires typing-extensions only below Python 3.12, so CPython 3.14 needs no
  backport package. No provider functionality is disabled.

No explicit runtime feature reduction was found in these build options.
Third-party license aggregation and embedded audit metadata differ from
conda-forge; the recipes retain their upstream license files. This comparison
does not establish exhaustive behavioral parity.

## Validation

Recipe tests check installed file ownership and runtime paths, command versions,
completion/man-page payloads, and these offline workflows:

- GitHub CLI configuration, aliases and a local shell alias without credentials.
- Chezmoi add/apply/status and template expansion in an isolated destination.
- Typst compilation with embedded fonts to PDF, SVG and PNG, HTML export and
  document queries without downloading packages or fonts.
- Pynvim's native MessagePack codec, greenlet switching, embedded Neovim RPC,
  automatic Python provider discovery and `:python3` buffer changes. The tests
  also check private interpreter relocation, isolation from public Python and
  channel libc++ resolution without GNU libstdc++.

All four focused local builds and their packaged tests passed against an
existing channel generation. The seven package-owned ELF files pass the glibc
2.28 baseline check, and the four payloads have no overlapping files. All 19
dependency-graph tests and 38 pipeline tests passed; the checked affected-build
plan selects exactly these four ordinary recipes.

These builds do not establish a new bootstrap fixed point. Package CI remains
responsible for validation against the generation selected by its affected-build
plan. GitHub remote API operations and external secret managers require
separately configured services.
