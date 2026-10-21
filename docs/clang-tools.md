# Clang language server and linter

The ordinary `recipes/clang-tools` recipe produces `clangd` and `clang-tidy`
23.1.3 for Linux x86_64. Install them with the channel selected explicitly:

```bash
pixi add --channel https://prefix.dev/black-desk clangd clang-tidy
```

Both packages depend on exactly Clang 23.1.3. They use its LLVM/Clang shared
libraries and compiler resource headers, so source and runtime versions must
advance together. The dependency is on the channel compiler; projects can still
describe their own compiler flags in `compile_commands.json`. Clang's default
host integration and explicit channel-build configuration retain their existing
roles. `clang-format` is already supplied by `clang`.

## Build and ownership

This is an ordinary recipe. It changes neither `seed-packages.tsv` nor
`bootstrap-order.json`, and does not modify the bootstrap Clang recipe. Its two
outputs share a Rattler-Build staging build, compiling Clang's standalone source
against the existing channel LLVM SDK. Clang/LLVM source versions match; the
compiler and SDK are not installed again.

Upstream CMake install components determine the payloads:

| Package      | Public commands                                            |
| ------------ | ---------------------------------------------------------- |
| `clangd`     | `clangd`                                                   |
| `clang-tidy` | `clang-tidy`, `clang-apply-replacements`, `run-clang-tidy` |

The linter also owns `lib/devkit/share/clang/clang-tidy-diff.py`.

The linter includes a channel Python dependency for its upstream Python helpers.
The language server does not require Python. Both use native relative RUNPATHs
to the channel's private runtime library directory and the glibc 2.28 build
sysroot.

As with upstream's Python helpers, combining exported diagnostics into one YAML
file additionally requires PyYAML in the selected interpreter. Exporting to a
directory and applying replacements do not require it; PyYAML is not bundled.

## Feature baseline

Compared with conda-forge's
[`clangdev` recipe at 846d5eb](https://github.com/conda-forge/clangdev-feedstock/tree/846d5eb2556c29463558d2bae20a3ef40192f71e/recipe),
also version 23.1.3, this build uses the same supported standalone Clang layout
with `clang-tools-extra` attached under `clang/tools/extra`. Both retain LLVM
shared-library linkage, RTTI and the upstream tool defaults. Our recipe builds
the requested `clangd`, `clang-tidy` and replacement-helper components rather
than conda-forge's larger `clang-tools` command collection.

Clangd retains its completion ranking model, background indexing and integrated
clang-tidy checks. Clang-tidy retains all upstream check modules, including
static-analyzer and query-based custom checks, and plugin support follows the
upstream Linux default. Remote gRPC indexing remains an upstream opt-in feature;
neither this recipe nor the inspected forge build enables it. No feature within
the requested tools is explicitly disabled. This source-option comparison does
not establish exhaustive behavioral parity.

## Validation

The installed clangd test communicates over LSP using only Python's standard
library. It loads a local compilation database, resolves the compiler's builtin
`stddef.h`, checks an integrated clang-tidy diagnostic, follows a symbol
definition, and diagnoses a changed document before shutting down normally.

The linter test exercises compilation-database loading, warning-to-error exit
status, automatic `nullptr` fixes, the null-dereference static analyzer, the
parallel `run-clang-tidy` helper, exported replacements and
`clang-apply-replacements`. Package tests also audit owned files and ELF runtime
paths. The affected-build plan must select both ordinary outputs without a
bootstrap rebuild.

Focused local validation compiled all three native commands against an existing
channel generation and passed both packages' installed tests. Repackaging reused
the compiled staging payload; the final channel-only CMake dependency discovery
and compiler capability checks were verified separately. A joint installation
also passed both functional suites after moving its prefix, with no overlapping
files among `clang`, `clangd` and `clang-tidy`. All three package-owned ELF
files meet the glibc 2.28 baseline and load channel LLVM, Clang, libc++ and
LLVM-libgcc after relocation, without GNU libstdc++.

The checked build plan selects only these two ordinary outputs. The 19
dependency graph tests and 38 pipeline tests pass. The complete final recipe
build remains an independent package CI check; these focused checks do not
establish a new bootstrap fixed point.
