# Ordinary recipe feature audit

Checked on 2026-10-12 for Linux x86_64, against fixed conda-forge feedstock
commits and the pinned upstream source options. This audits recipes scheduled
after bootstrap; it does not establish a successful build against the final
self-hosted generation. Existing focused build results are separate evidence.

At the maintainer's request, the prebuilt Python distribution, rustup manager
and downloaded Rust toolchain are excluded. rust-toolchain-lock has no compiled
features. Rust applications built from source remain in scope, as does B4's
application dependency closure. All 12 remaining recipes were reviewed.

"No explicit runtime feature reduction found" means the inspected build options
do not switch off an application feature. It is not a claim of exhaustive
behavioral parity. Differences in LTO, stripping, compiler choice, library
linkage, dependency versions and audit metadata are recorded separately from
missing functionality. Baseline versions differ for several feedstocks; old
dependency lists are not copied blindly into newer recipes.

| Recipe                                          | Our version / forge version | Finding                                                     | Evidence                                                                                                                                                                                                                                                                                                                                                                                       |
| ----------------------------------------------- | --------------------------- | ----------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [b4](../recipes/b4/recipe.yaml)                 | 0.16.0 / 0.15.2             | Confirmed packaging/runtime gaps                            | Core 0.16 dependencies are locked, but TUI extras and completion generation dependencies are absent; no public man page or completions are installed. [Forge recipe](https://github.com/conda-forge/b4-feedstock/tree/81cdb9a79d1be70d751b6f3d6d18f00a8240ef8f/recipe).                                                                                                                        |
| [difftastic](../recipes/difftastic/recipe.yaml) | 0.71.0 / 0.71.0             | No explicit runtime feature reduction found                 | Both use Cargo defaults. Forge adds fat LTO, symbol stripping and _BSD_SOURCE; the latter needs a portability check when updating native dependencies. [Forge recipe](https://github.com/conda-forge/difftastic-feedstock/tree/bbbd7fe61191a44dbaed674e779d57848e527e9f/recipe).                                                                                                               |
| [fd](../recipes/fd/recipe.yaml)                 | 10.5.0 / 10.5.0             | No explicit runtime feature reduction found                 | Both use Cargo defaults. Forge adds fat LTO/stripping and a glibc startup-link workaround. Our sysroot/linker differs; these are not disabled application features. [Forge recipe](https://github.com/conda-forge/fd-find-feedstock/tree/e2196f5747292206232c4d12ba6b0a74c1716587/recipe).                                                                                                     |
| [git](../recipes/git/recipe.yaml)               | 2.56.0 / 2.56.0             | Confirmed feature and packaging gaps                        | Our NO_TCLTK, NO_PYTHON and NO_GETTEXT disable helpers/GUI/translations. Forge also installs manuals, HTML documentation and Bash completion which we do not install. [Forge recipe](https://github.com/conda-forge/git-feedstock/tree/71aa484678c3d0372e48ad8053b1ce6411f20b80/recipe).                                                                                                       |
| [go](../recipes/go/recipe.yaml)                 | 1.27.1 / 1.27.2             | Toolchain integration difference                            | We retain the official distribution. Forge builds cgo/nocgo variants and patches flag inheritance, default paths and linker flag handling; our repack has none of that conda integration. [Forge recipe](https://github.com/conda-forge/go-feedstock/tree/9c80ca35f362ced743db27c7cb5260141a93f755/recipe).                                                                                    |
| [gopls](../recipes/gopls/recipe.yaml)           | 0.23.0 / 0.23.0             | No explicit runtime feature reduction found                 | Forge uses go-nocgo; our CGO_ENABLED=0 agrees with that baseline. No build tags are suppressed. Our extra Go runtime dependency makes workspace loading explicit. [Forge recipe](https://github.com/conda-forge/gopls-feedstock/tree/22aa4c89d38eadb1f9b93496895daf4b652c777c/recipe).                                                                                                         |
| [just](../recipes/just/recipe.yaml)             | 1.58.0 / 1.58.0             | No explicit runtime feature reduction found                 | Both use Cargo defaults and install Bash/Fish/Zsh completions and a man page. Thin versus fat LTO changes optimization; forge also embeds cargo-auditable metadata. [Forge recipe](https://github.com/conda-forge/just-feedstock/tree/fcfb5c5511bf23f7df8e5f55bc6d96d2762e200a/recipe).                                                                                                        |
| [lazygit](../recipes/lazygit/recipe.yaml)       | 0.65.1 / 0.66.1             | CGO behavior requires verification                          | Forge uses its ordinary Go compiler; our recipe forces CGO_ENABLED=0. DNS/NSS differences are possible, but no CLI feature removal has been demonstrated. Vendoring and version strings are packaging differences. [Forge recipe](https://github.com/conda-forge/lazygit-feedstock/tree/92f94af67e3acd85c10812f19d76597209c57391/recipe).                                                      |
| [pcre2](../recipes/pcre2/recipe.yaml)           | 10.49 / 10.47               | Feature and development-interface gaps corrected            | Our CMake build enables all widths, gzip/bzip2 input, libedit, JIT/Unicode and relocatable shared/static CMake exports. Forge enables all widths and provides zlib/bzip2 and CMake exports. [Forge recipe](https://github.com/conda-forge/pcre2-feedstock/tree/1036df63759c1365071c7531a6e01fcca90f28a1/recipe).                                                                               |
| [ripgrep](../recipes/ripgrep/recipe.yaml)       | 15.2.0 / 15.2.0             | PCRE2 feature enabled                                       | Both builds pass --features pcre2. Our binding selects the channel shared library and package tests exercise lookaround through rg -P. Our completions/man page are otherwise retained. [Forge recipe](https://github.com/conda-forge/ripgrep-feedstock/tree/78115297cdb194ca1851ed7872c0caadd5a33275/recipe).                                                                                 |
| [uv](../recipes/uv/recipe.yaml)                 | 0.12.22 / 0.13.0            | No runtime feature reduction found in pinned upstream flags | Our performance-only build excludes test-defaults, which pinned upstream documents as test-only. self-update is also absent from upstream defaults and should be disabled for package-manager builds. Forge uses channel zstd; ours uses the locked native dependency build. [Forge recipe](https://github.com/conda-forge/uv-feedstock/tree/1710613e2e6c6ef94f3fd3a1313e7fa5a9e5f5b8/recipe). |
| [yazi](../recipes/yazi/recipe.yaml)             | 26.9.1 / 26.9.1             | External-tool dependency coverage differs                   | Both keep default Cargo features. Forge exposes optional preview/search/clipboard/metadata/plugins dependency groups. We provide Git/fd/ripgrep but not those complete groups. Missing helpers affect available previews and integrations, not compiled-in features. [Forge recipe](https://github.com/conda-forge/yazi-feedstock/tree/ceae4efb5ef5a88dd0e3ed3ba87fe79e64c4be04/recipe).       |

## Confirmed corrections to plan

PCRE2 now builds with upstream CMake, preserving the exact-library-path policy
and version-isolated headers. All three widths expose shared/static libraries,
pkg-config metadata and pcre2-config options. Channel zlib/bzip2 enable
compressed pcre2grep input, and libedit enables interactive pcre2test input.
JIT, Unicode and forge-compatible -O3 remain enabled. Focused upstream and
package tests pass, including all widths, POSIX, shared/static CMake consumers
and compressed input.

Ripgrep enables the pcre2 Cargo feature, requires channel pkg-config metadata
before Cargo runs, and selects dynamic linkage. Package tests exercise rg -P
lookaround, report the PCRE2 version and inspect channel library resolution. The
focused channel build and package tests pass, including dynamic linkage to the
channel PCRE2 library.

Git should restore gettext output translations and Python helpers, ship its Bash
completion, and install the matching upstream man/HTML archives. Forge uses
libiconv as well; check text conversion against the channel implementation when
aligning library selection. Forge sets CSPRNG_METHOD=openssl to support an older
glibc baseline; our getrandom path is compatible with our glibc 2.28 baseline
and does not itself remove a feature. Restoring gitk/git-gui requires a channel
Tcl/Tk interpreter and its GUI dependencies, which are not currently recipes in
this repository. Merely deleting NO_TCLTK would not make those commands usable.
Optional Perl integrations such as git svn also require external modules; the
inspected forge recipe does not declare those either.

B4 0.16.0 declares completion (shtab) and tui (textual[syntax], rich) extras.
Our wheel/lock includes the current core dependencies but neither extra. Forge's
older B4 recipe installs textual, generates Bash/Zsh completions and installs
the man page. Do not reintroduce forge's old git-filter-repo dependency without
checking the newer upstream: 0.16 replaces it with pygit2/ezgb/liblore. Optional
GnuPG/git-bug integrations should be distinguished from forge-enabled features;
their helper executables are not declared by the inspected baseline.

Yazi retains its default binary features, but its default scripts call external
programs. Forge's optional groups cover file, ffmpeg, imagemagick, poppler,
resvg, 7zip, jq, chafa, fzf, zoxide, xclip/xsel, mediainfo and exiftool, in
addition to Git/fd/ripgrep. These are opt-in dependencies on forge, not all
installed by a plain yazi install. Making the same groups available in our
channel requires an explicit expansion of the ordinary package inventory; none
is silently added by this audit.

## Differences that need targeted validation

Lazygit's forced pure-Go build differs from forge's ordinary Go build. Compare
the relevant native DNS/NSS behavior before deciding whether CGO_ENABLED=0 is
acceptable. If restoring cgo, declare channel Clang/sysroot inputs and pass
explicit compiler/linker flags rather than allowing Go to discover host GCC.
Gopls intentionally uses a no-cgo baseline on forge and needs no such change
just to align that setting.

Go's official repack retains cgo capability, but does not include forge's
conda-aware compiler/flag activation and source patches. Validate downstream cgo
builds with explicit channel Clang and our sysroot. Retain the user-facing
host-build policy when deciding whether any integration is needed. Fortran
compiler coverage in forge's cgo tests is another toolchain scope difference;
this audit does not add a Fortran compiler or claim those tests are covered.

UV's pinned
[Cargo features](https://github.com/astral-sh/uv/blob/0.12.22/crates/uv/Cargo.toml)
explicitly identify test-defaults as test-only and self-update as reserved for
its own installer. The inspected forge default build does not enable self-update
either. The runtime feature set is therefore not reduced by our performance-only
selection. Before running upstream UV tests, reconsider which test features and
fixtures that test invocation needs. The latest forge baseline is 0.13.0; no
0.12.22 recipe was found in the last 50 changes to its recipe, so
version-specific behavior is checked against pinned upstream rather than
inferred from the newer feedstock.

## Execution status

The audit led to PCRE2 and ripgrep corrections within the existing inventory.
Git non-GUI corrections remain planned; GUI/Tcl/Tk expansion is not approved.
Yazi external-tool availability is outside the current package promise. No full
bootstrap was restarted locally. Focused validation uses a previously completed
channel and does not establish final-generation self-hosting; CI owns that
check.

## Neovim addition

The subsequent [Neovim 0.12.6 audit](neovim.md#feature-baseline) compares the
editor against a fixed conda-forge `nvim` revision. LuaJIT, translations and all
default Tree-sitter parsers remain enabled. Libraries and parsers now have
independent recipes; the editor uses shared channel libraries and parser runtime
packages. Neovim-pinned upstream LuaJIT differs from forge's OpenResty fork;
full fork-specific compatibility is not established. This addition is outside
the original 12-recipe snapshot above.

## Additional channel tools

The [gh, pynvim, Typst and chezmoi audit](channel-tools.md#feature-baseline)
compares these additions against fixed conda-forge feedstock revisions and
upstream build options. Both Go applications keep the no-cgo baseline and shell
completions. Typst retains default features, embedded fonts and dynamic OpenSSL.
Pynvim includes both native dependencies in its private environment and the
upstream Neovim provider discovery command. These additions are outside the
original 12-recipe snapshot.
