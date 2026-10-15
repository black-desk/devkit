# Native development installation audit

All 54 recipe directories were reviewed for development installation and
metadata generation. This audit concerns installation paths, not another feature
comparison with conda-forge. Existing feature choices and runtime/plugin layouts
are preserved.

Development headers and metadata are installed directly into `lib/devkit` using
upstream options or source patches. `stage-development.py` remains responsible
for relative aliases to public runtime libraries, and for static/Libtool
archives in projects whose libdir controls both shared and static installation.
Moving those interfaces after installation avoids redirecting runtime libraries.
Libtool `.la` directory fields follow their archive location.

The staging script no longer rewrites public config helpers. Native hidden
metadata is left untouched. There is no metadata-rewrite fallback. Newly
installed public headers or metadata cause staging to fail; recipes must
generate their final paths before installation.

| Recipe                | Installation treatment                                                                                                                                                |
| --------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `b4`                  | Executable/application output; no public C/C++ development interface. Preserve native installation and runtime resources.                                             |
| `bzip2`               | Make install directory variables for headers/archive/man pages; explicit runtime library install remains.                                                             |
| `c-ares`              | Native CMake includedir; patched metadata/archive install destinations and generated pc templates. CMake exports derive their installed paths.                        |
| `ca-certificates`     | Data/configuration-only output; no compiled development interface to relocate.                                                                                        |
| `clang`               | CMake include/package options; source archive install rules and llvm-config template. Compiler resources remain upstream.                                             |
| `cmake`               | Executable/application output; no public C/C++ development interface. Preserve native installation and runtime resources.                                             |
| `cppdap`              | Native CMake includedir; patched metadata/archive install destinations and generated pc templates. CMake exports derive their installed paths.                        |
| `curl`                | Native includedir and applicable metadata install directory overrides; source metadata patches where exported interfaces exist. Shared runtime libdir remains public. |
| `difftastic`          | Executable/application output; no public C/C++ development interface. Preserve native installation and runtime resources.                                             |
| `expat`               | Native includedir and applicable metadata install directory overrides; source metadata patches where exported interfaces exist. Shared runtime libdir remains public. |
| `fd`                  | Executable/application output; no public C/C++ development interface. Preserve native installation and runtime resources.                                             |
| `gettext`             | Native includedir and applicable metadata install directory overrides; source metadata patches where exported interfaces exist. Shared runtime libdir remains public. |
| `git`                 | Executable/application output; no public C/C++ development interface. Preserve native installation and runtime resources.                                             |
| `gnuconfig`           | Data/configuration-only output; no compiled development interface to relocate.                                                                                        |
| `go`                  | Imported upstream toolchain payload; retain tool-internal resources and upstream layout. No newly built public library interface.                                     |
| `gopls`               | Executable/application output; no public C/C++ development interface. Preserve native installation and runtime resources.                                             |
| `icu`                 | Native includedir; patched installed Makefile/pc templates and separate installed pkgdata.inc generation.                                                             |
| `jsoncpp`             | Native CMake includedir; patched metadata/archive install destinations and generated pc templates. CMake exports derive their installed paths.                        |
| `just`                | Executable/application output; no public C/C++ development interface. Preserve native installation and runtime resources.                                             |
| `keyutils`            | Native INCLUDEDIR; patched pc template/destination. Runtime library layout remains upstream.                                                                          |
| `krb5`                | Native includedir and applicable metadata install directory overrides; source metadata patches where exported interfaces exist. Shared runtime libdir remains public. |
| `lazygit`             | Executable/application output; no public C/C++ development interface. Preserve native installation and runtime resources.                                             |
| `libarchive`          | Native CMake includedir; patched metadata/archive install destinations and generated pc templates. CMake exports derive their installed paths.                        |
| `libcxx`              | Native LIBCXX/LIBCXXABI_INSTALL_INCLUDE_DIR options; no header move or export rewrite.                                                                                |
| `libedit`             | Native includedir and applicable metadata install directory overrides; source metadata patches where exported interfaces exist. Shared runtime libdir remains public. |
| `libev`               | Native includedir and applicable metadata install directory overrides; source metadata patches where exported interfaces exist. Shared runtime libdir remains public. |
| `libiconv`            | Native includedir and applicable metadata install directory overrides; source metadata patches where exported interfaces exist. Shared runtime libdir remains public. |
| `liblzma`             | Native includedir and applicable metadata install directory overrides; source metadata patches where exported interfaces exist. Shared runtime libdir remains public. |
| `libnghttp2`          | Native includedir and applicable metadata install directory overrides; source metadata patches where exported interfaces exist. Shared runtime libdir remains public. |
| `libpsl`              | Native includedir and applicable metadata install directory overrides; source metadata patches where exported interfaces exist. Shared runtime libdir remains public. |
| `libssh2`             | Native CMake includedir; patched metadata/archive install destinations and generated pc templates. CMake exports derive their installed paths.                        |
| `libuv`               | Native CMake includedir; patched metadata/archive install destinations and generated pc templates. CMake exports derive their installed paths.                        |
| `libxcrypt`           | Native includedir and applicable metadata install directory overrides; source metadata patches where exported interfaces exist. Shared runtime libdir remains public. |
| `libxml2`             | Native includedir and applicable metadata install directory overrides; source metadata patches where exported interfaces exist. Shared runtime libdir remains public. |
| `llvm-libgcc`         | Native LIBUNWIND_INSTALL_INCLUDE_DIR option. Compatibility aliases/meta output remain deliberate.                                                                     |
| `lz4-c`               | Native INCLUDEDIR and PKGCONFIGDIR; patched pc template.                                                                                                              |
| `lzo`                 | Native CMake includedir; patched metadata/archive install destinations and generated pc templates. CMake exports derive their installed paths.                        |
| `make`                | Native includedir and applicable metadata install directory overrides; source metadata patches where exported interfaces exist. Shared runtime libdir remains public. |
| `ncurses`             | Native includedir/pc destination; patched nested-header support and pc/config templates. Preserve narrow/wide trees.                                                  |
| `ninja`               | Executable/application output; no public C/C++ development interface. Preserve native installation and runtime resources.                                             |
| `openssl`             | Patched native header/exporter install rules; generated pc/CMake metadata agrees with hidden paths. Providers stay public.                                            |
| `pcre2`               | Native CMake includedir; patched metadata/archive install destinations and generated pc templates. CMake exports derive their installed paths.                        |
| `perl`                | Patch configpm to generate separate consumer Config modules; install those explicitly and preserve build-time modules.                                                |
| `pkgconf`             | Executable/application output; no public C/C++ development interface. Preserve native installation and runtime resources.                                             |
| `python`              | Imported upstream toolchain payload; retain tool-internal resources and upstream layout. No newly built public library interface.                                     |
| `rhash`               | Native INSTALL_INCDIR/pkgconfigdir; patched configure pc template.                                                                                                    |
| `ripgrep`             | Executable/application output; no public C/C++ development interface. Preserve native installation and runtime resources.                                             |
| `rust-toolchain-lock` | Data/configuration-only output; no compiled development interface to relocate.                                                                                        |
| `rustup`              | Imported upstream toolchain payload; retain tool-internal resources and upstream layout. No newly built public library interface.                                     |
| `sysroot`             | Imported upstream payload; keep tool-internal resources/layout. Sysroot is deliberately excluded from package ELF/layout checks.                                      |
| `uv`                  | Executable/application output; no public C/C++ development interface. Preserve native installation and runtime resources.                                             |
| `yazi`                | Executable/application output; no public C/C++ development interface. Preserve native installation and runtime resources.                                             |
| `zlib`                | Native CMake includedir; patched metadata/archive install destinations and generated pc templates. CMake exports derive their installed paths.                        |
| `zstd`                | Native CMake includedir; patched metadata/archive install destinations and generated pc templates. CMake exports derive their installed paths.                        |

## Validation

- Applied complete recipe source patch lists to pristine pinned source trees.
- Actually built and installed ten CMake libraries: c-ares, cppdap, jsoncpp,
  libarchive, libssh2, libuv, lzo, pcre2, zlib and zstd. Checked package layout,
  physically relocated prefixes, loaded generated CMake exports, and resolved
  pkg-config headers/libraries. Some dependency-heavy validation builds use a
  reduced test surface; recipe feature flags are unchanged.
- ICU: actual build/install and package layout/ELF checks; checked installed
  Makefile.inc/pkgdata.inc consumer flags and icu-config output.
- OpenSSL: generated exporters through its actual Configure/Make process; loaded
  its CMake package after relocating an export fixture, checking imports and
  public provider paths.
- expat, libxml2 and libxcrypt: actual Clang build/install, package layout/ELF
  checks and generated pc paths.
- ncurses: actual narrow/wide builds and installed headers; re-generated pc
  files with the final patch and checked relocatable paths and absence of
  bootstrap flags.
- LLVM/Clang: configured patched sources and checked generated installed
  include/library/package paths, without compiling the compiler.
- Perl: generated separate consumer Config modules using patched configpm;
  installed and loaded them with a complete local Clang-built Perl 5.44.
  Verified fresh/repeated installation, physical prefix relocation, unchanged
  build Config modules and unrelated modules with the same basename. This
  installer validation uses host dependencies, not the bootstrap environment.
- Repository packaging/pipeline tests, shell syntax, recipe rendering and patch
  application checks accompany the change.

These targeted checks do not replace the dirty/result/selfhost CI rebuild and
stage-level installed behavior tests. LLVM/Clang has not been rebuilt locally
for this installation change.

Post-link ELF exceptions are separate from development installation: existing
annotated finalize-elf uses remain until each build system supports the required
per-file installed RUNPATH. See [development-layout.md](development-layout.md).

Unified source patches retain upstream context whitespace verbatim. The shared
clean check excludes `*.patch`; patch applicability is verified separately.
Removing whitespace from patch context can prevent hunks from applying.

RHash's default `install` target omits its generated `.pc` file. The recipe
explicitly invokes upstream `install-pkg-config`, which installs directly into
the configured hidden metadata directory. This target was verified locally.

Perl's `configpm` generator reads individual values from `config.sh`. In
consumer mode it canonicalizes the compiler settings before serialization and
emits relocation support from source templates. It writes separate Config
modules outside the build's `lib` tree. The install rule selects these two
artifacts explicitly; neither the generic copy routine nor any installed file
content is modified. The normal generator mode retains bootstrap settings for
building and testing Perl. Other modules named `Config.pm` remain unchanged.

ICU uses its upstream `INVOKE`, `PKGDATA_INVOKE` and `INSTALLED_INVOKE` wrappers
for build-time library loading. The recipe does not override them or add
source-tree RUNPATH entries to global `LDFLAGS`. Installed ELF finalization and
tests remain independent of the build-time loader environment. This change does
not merge the build and consumer pkgdata configurations.

Validated the ICU wrapper change with a complete local Clang build and install
using the pinned 78.3 source and recipe patches. Build logs show upstream
`LD_LIBRARY_PATH` wrappers executing `icupkg` and `pkgdata`; both generated and
installed pkgdata configurations contain no source-tree paths or RUNPATH flags.
After the existing ELF finalization, installed `icuinfo` runs without a loader
environment override. This check uses host build dependencies.

Keep the public `pkgdata` tool and the channel configuration in the hidden
development directory. The optional library-generation modes do not require
adding a compiler runtime dependency to ICU, just as the distribution package
does not depend on GCC. Default configuration discovery remains host-oriented;
channel builds explicitly select the channel configuration.

MIT krb5 uses the case-sensitive Make variable `PKGCONFIG_DIR`, not Automake's
`pkgconfigdir`. Pass that variable to `make install` so all eight generated pc
files install directly into `lib/devkit/lib/pkgconfig`. Removing the staging
fallback exposed the previously ignored lowercase override. Verified the pinned
source's configured `install-mkdirs` and build-tools installation targets
locally: all eight pc files land directly in the hidden directory with their
native generated prefix definitions.

Zlib's upstream installation-consumer tests explicitly search their temporary
installation's `lib/devkit` prefix. Their original reliance on searching only
`CMAKE_INSTALL_PREFIX` no longer finds the relocated CONFIG package. All five
consumer configure commands select the fixture's hidden prefix, rather than an
input generation's zlib or a host library. No tests are disabled. Locally
reproduced the selfhost failure (10 failed or blocked tests), then rebuilt with
the corrected search paths: all 18 upstream CTest tests pass.

## Installation-consumer test audit

After the selfhost zlib failure, reviewed every recipe's build/test entry points
and the pinned, checksum-verified upstream CMake/test definitions for the eleven
other CMake projects below. This checks nested consumer discovery, not just the
outer recipe's `CMAKE_PREFIX_PATH`: cache arguments are not automatically passed
to a nested CMake invocation.

| Project    | Enabled test/discovery path                                                                           | Finding                                                                                                                                         |
| ---------- | ----------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| zlib       | Installs a temporary fixture and launches five nested consumer configurations.                        | Fixed each configure command to search that fixture's `lib/devkit`; all 18 tests pass locally.                                                  |
| c-ares     | Recipe runs an explicitly compiled installed-library probe; upstream GoogleTest suite is not enabled. | No nested installation consumer.                                                                                                                |
| cppdap     | Build-tree GoogleTest executable; separate test-only GTest installation.                              | `GTest_DIR` explicitly selects the test fixture; `jsoncpp_DIR` explicitly selects the channel configuration.                                    |
| jsoncpp    | Build-tree unit executable and Python-driven reader/writer tests.                                     | No installed-package discovery in enabled tests.                                                                                                |
| libarchive | Build-tree archive/command test executables.                                                          | No nested installation consumer; outer dependency discovery uses the hidden prefix and explicit Find-module paths.                              |
| libssh2    | Build-tree unit executables and script tests.                                                         | No nested installation consumer; optional SSH integration scope is unchanged.                                                                   |
| libuv      | Selected `uv_test` executable in the build tree.                                                      | No nested installation consumer.                                                                                                                |
| lzo        | Build-tree compression/example executables.                                                           | No nested installation consumer.                                                                                                                |
| pcre2      | Build-tree regression scripts/JIT/POSIX executables; repository installed-consumer tests.             | Installed shared/static consumers explicitly set `PCRE2_DIR` to the hidden configuration and `PKG_CONFIG_LIBDIR` to hidden pc files.            |
| zstd       | Build-tree benchmark/fuzzer/stream tests and CLI script.                                              | No nested installation consumer.                                                                                                                |
| CMake      | Selected CTest parallel/download smoke tests; repository discovery tests.                             | Parallel fixture configures a self-contained test project; discovery tests explicitly distinguish host defaults from the hidden channel prefix. |
| Ninja      | Build-tree `ninja_test`.                                                                              | No nested installation consumer.                                                                                                                |

The other recipes use Make/Autotools, Meson, Cargo, Go, imported payloads or
data-only installation. Reviewed their repository test entry points for CMake
and pkg-config consumers as well: existing explicit hidden search paths remain
in place. LLVM/Clang runtime probes select the channel compiler configuration
explicitly; they do not use a temporary installed-package CMake fixture.

No second instance of zlib's missing nested installation prefix was found. This
source/recipe audit does not claim all upstream suites have run locally;
selfhost and the later smoke/ordinary jobs remain required validation.
