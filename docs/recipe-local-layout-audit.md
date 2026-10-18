# Recipe-local development layout migration

Work starts from `1b85f68978d6` on the isolated branch
`experiment/recipe-local-development-layout`. Commit `1b85f68978d6` is the
rollback reference; this experiment does not change the seed manifest. After
local validation, the maintainer requested publishing these commits to the
existing PR #33 branch, `experiment/devkit-development-prefix`.

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

## Per-recipe review

All 54 recipe definitions and their install scripts were reviewed. 33 recipes
had shared development staging or layout-only patches to replace; the other 21
retain their established application, data, imported-toolchain or functional
configuration behavior. The seed manifest is unchanged. The common development
staging script and its obsolete unit tests are removed, not expanded. Existing
package/ELF audits remain independent shared checks.

Installed pkg-config output now retains upstream `-L`/`-l` syntax, generated
private libraries and Requires relationships. Tests expecting an exact shared
filename are updated to upstream output where applicable; real shared/static
consumer compilation and ELF checks establish which primary library was used.
Clang and Perl retain specifically documented functional query/configuration
patches: a file move cannot change compiled llvm-config lookup behavior or the
seed compiler information encoded in Perl's Config modules.

| Recipe                | Treatment                                                                                                                                                                                      |
| --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `b4`                  | Imported wheel/tool environment; retain Python-internal resources and application launcher.                                                                                                    |
| `bzip2`               | Unmodified upstream installer; move bzlib.h, archive, linker aliases and man directory locally.                                                                                                |
| `c-ares`              | Keep supported header install options; move this recipe's selected development interfaces and repair installed pc/CMake location fields locally. Preserve generated dependencies.              |
| `ca-certificates`     | Data-only upstream payload; no development interface move.                                                                                                                                     |
| `clang`               | Native header/package directories; move only compiler archives/interfaces and repair archive exports locally. Retain functional llvm-config lookup patch.                                      |
| `cmake`               | Normal executable/module installation, existing host-default discovery behavior and RUNPATH remain.                                                                                            |
| `cppdap`              | Keep supported header install options; move this recipe's selected development interfaces and repair installed pc/CMake location fields locally. Preserve generated dependencies.              |
| `curl`                | Use upstream dependency detection, pc Requires and curl-config output. Move metadata/helper locally; repair query paths. Test helper and pc static consumers.                                  |
| `difftastic`          | Application-only install; retain existing executable/resources layout and RUNPATH handling. No ordinary development metadata or library interfaces exported.                                   |
| `expat`               | Native header/metadata options; move interfaces/archives locally and repair generated CMake header paths.                                                                                      |
| `fd`                  | Application-only install; retain existing executable/resources layout and RUNPATH handling. No ordinary development metadata or library interfaces exported.                                   |
| `gettext`             | Native includedir; locally stage reviewed library names, keeping versioned private runtime DSOs public. This install does not export a pc file.                                                |
| `git`                 | Normal application/libexec/resources layout, existing per-target RUNPATH and feature choices remain.                                                                                           |
| `gnuconfig`           | Data/scripts only; no development interface move.                                                                                                                                              |
| `go`                  | Imported GOROOT; retain compiler-internal archives/headers and public launchers.                                                                                                               |
| `gopls`               | Application-only install; retain existing executable/resources layout and RUNPATH handling. No ordinary development metadata or library interfaces exported.                                   |
| `icu`                 | Native header/pkglibdir options; move pc/interfaces locally. Repair only installed Makefile.inc/pkgdata.inc consumer settings; preserve build-time data configuration.                         |
| `jsoncpp`             | Native header option; move metadata, archives and exported object files locally. Repair matching CMake paths.                                                                                  |
| `just`                | Application-only install; retain existing executable/resources layout and RUNPATH handling. No ordinary development metadata or library interfaces exported.                                   |
| `keyutils`            | Keep supported header install options; move this recipe's selected development interfaces and repair installed pc/CMake location fields locally. Preserve generated dependencies.              |
| `krb5`                | Native includedir/metadata directory options; repair pc variables and krb5-config after installation. Runtime paths stay public.                                                               |
| `lazygit`             | Application-only install; retain existing executable/resources layout and RUNPATH handling. No ordinary development metadata or library interfaces exported.                                   |
| `libarchive`          | Move upstream-installed public headers and development files; retain generated private dependency list. Test shared and metadata-driven static consumers.                                      |
| `libcxx`              | Native libc++ header options; move archives/linker scripts and recompute relative aliases locally.                                                                                             |
| `libedit`             | Keep supported header install options; move this recipe's selected development interfaces and repair installed pc/CMake location fields locally. Preserve generated dependencies.              |
| `libev`               | Keep supported header install options; move this recipe's selected development interfaces and repair installed pc/CMake location fields locally. Preserve generated dependencies.              |
| `libiconv`            | Keep supported header install options; move this recipe's selected development interfaces and repair installed pc/CMake location fields locally. Preserve generated dependencies.              |
| `liblzma`             | Keep supported header install options; move this recipe's selected development interfaces and repair installed pc/CMake location fields locally. Preserve generated dependencies.              |
| `libnghttp2`          | Keep supported header install options; move this recipe's selected development interfaces and repair installed pc/CMake location fields locally. Preserve generated dependencies.              |
| `libpsl`              | Keep supported header install options; move this recipe's selected development interfaces and repair installed pc/CMake location fields locally. Preserve generated dependencies.              |
| `libssh2`             | Keep supported header install options; move this recipe's selected development interfaces and repair installed pc/CMake location fields locally. Preserve generated dependencies.              |
| `libuv`               | Native versioned includedir; locally move pc/config/archive files and repair export paths. Preserve pthread/dl/rt/m generated by upstream.                                                     |
| `libxcrypt`           | Keep supported header install options; move this recipe's selected development interfaces and repair installed pc/CMake location fields locally. Preserve generated dependencies.              |
| `libxml2`             | Keep versioned includedir; flatten upstream libxml2/libxml nesting locally; repair pc, CMake and xml2-config paths. Remove exact-DSO Libtool workaround once dependencies retain -L/-l output. |
| `llvm-libgcc`         | Native libunwind header option; move GCC-compatible linker interfaces/archives, preserve compiler-rt resources and runtime SONAMEs.                                                            |
| `lz4-c`               | Keep supported header install options; move this recipe's selected development interfaces and repair installed pc/CMake location fields locally. Preserve generated dependencies.              |
| `lzo`                 | Keep supported header install options; move this recipe's selected development interfaces and repair installed pc/CMake location fields locally. Preserve generated dependencies.              |
| `make`                | Existing includedir option fully handles gnumake.h; remove shared staging without adding a replacement move.                                                                                   |
| `ncurses`             | Use upstream normal include layout for both builds, then move ncurses/ncursesw headers locally. Repair consumer paths and filter build-only flags in installed metadata/helpers.               |
| `ninja`               | Normal executable installation; existing native install RUNPATH remains.                                                                                                                       |
| `openssl`             | Move upstream-installed headers, archives, pc/CMake metadata and linker interfaces locally; retain public engines/provider modules and their metadata paths.                                   |
| `pcre2`               | Native versioned includedir; move exports/archives/pc/helper locally. Repair helper/export paths and retain generated dependencies for all widths/POSIX.                                       |
| `perl`                | No ordinary development-prefix move. Retain functional canonical compiler Config-module generation and language-internal layout.                                                               |
| `pkgconf`             | CLI-only install; internal static libpkgconf is not exported. Existing host-default search configuration remains.                                                                              |
| `python`              | Imported uv-managed Python tree; retain language-internal headers/libraries and existing imported-payload check scope.                                                                         |
| `rhash`               | Keep supported header install options; move this recipe's selected development interfaces and repair installed pc/CMake location fields locally. Preserve generated dependencies.              |
| `ripgrep`             | Application-only layout; retain RUNPATH. Update the channel PCRE2 preflight for upstream -L/-l metadata; installed tests require a channel libpcre2 dynamic dependency.                        |
| `rust-toolchain-lock` | Metadata/lock carrier; no development interface move.                                                                                                                                          |
| `rustup`              | Imported upstream manager; retain private runtime payload and public launcher. No development interface move.                                                                                  |
| `sysroot`             | Imported Rocky filesystem/sysroot layout; no staging or ELF rewrite.                                                                                                                           |
| `uv`                  | Application-only install; retain existing executable/resources layout and RUNPATH handling. No ordinary development metadata or library interfaces exported.                                   |
| `yazi`                | Application-only install; retain existing executable/resources layout and RUNPATH handling. No ordinary development metadata or library interfaces exported.                                   |
| `zlib`                | Keep supported header install options; move this recipe's selected development interfaces and repair installed pc/CMake location fields locally. Preserve generated dependencies.              |
| `zstd`                | Keep supported header install options; move this recipe's selected development interfaces and repair installed pc/CMake location fields locally. Preserve generated dependencies.              |

## Validation

Local result-variant builds use successful selfhost CI run `38943793434` (commit
`a385d3b602fe`) as the baseline, with already validated newly built package
metadata used for integration where needed. Upstream build-tree suites are
skipped for this focused layout work (`DEVKIT_RUN_TESTS=0`); installed package
tests run normally. This is not a fresh dirty/result/selfhost bootstrap.

All 33 changed recipe definitions render for both dirty/result variants. Shell
and inline Python syntax, referenced-patch paths and whitespace checks pass. The
remaining shared repository tests pass (37 tests).

All 32 affected recipes other than Clang were rebuilt locally and passed their
installed package tests, including ownership/layout/RUNPATH checks and their
consumer probes. Libarchive's static consumer uses generated pkg-config private
dependencies. Curl's shared and static consumers use curl-config; a separate
static consumer uses pkg-config. Restoring upstream Requires.private also
restores dependency header flags, which the tests now permit. OpenSSL provider
loading and PCRE2's CMake shared/static consumers for all widths and POSIX pass.
Libxml2 was rebuilt against the new zlib metadata; curl uses the new libpsl and
libnghttp2 metadata. These integrations no longer require the old exact-DSO
Libtool workaround or hand-maintained dependency lists.

A separate installed environment passed 14 CMake configure/build/run consumers
covering c-ares shared/static, JsonCpp shared/static, cppdap, libuv
shared/static, zlib shared/static, zstd shared/static, libssh2, expat and
OpenSSL. Physically moving that environment to another prefix and rebuilding all
14 consumers also passed. Queries for all 49 installed pc files after that move
resolve existing include/library directories and contain no original test
prefix. This does not claim that absolute paths in every auxiliary file survive
a raw directory move: Conda prefix replacement remains necessary for recorded
absolute prefixes.

Clang was not rebuilt locally in full. A separate fixture reconstructed upstream
library/export locations from the previous successful Clang payload and ran the
exact new recipe-local install transformation. LLVM, Clang and LLD CMake exports
loaded successfully, a static LLVMSupport consumer compiled and ran, and
llvm-config reported the hidden development directories. This checks the
archive/export transformation against existing artifacts, not a fresh compiler
build. The subsequent full bootstrap CI result is recorded below.

## CI integration follow-up

Run `39051401807` passed dirty, result, selfhost and the independent test job,
including the full compiler rebuild. The subsequent application build stopped at
ripgrep's pre-Cargo PCRE2 check: it still required an absolute `.so` filename
from pkg-config. Check the upstream `-L` and `-lpcre2-8` tokens instead; keep
`PCRE2_SYS_STATIC=0` and the installed ELF dependency assertion. A repository
search found no other pkg-config assertions requiring that old exact-DSO output.
Local validation reproduced the old failed assertion against the newly built
PCRE2 package, then passed the corrected recipe preflight. A consumer compiled
using its pkg-config flags passed Unicode/JIT/matching checks and loaded
`libpcre2-8.so.0` from the channel environment. Recipe rendering and shell
syntax checks passed. This does not rebuild ripgrep itself; full application CI
remains required after this correction.

## Recipe script organization

Keep straightforward substitutions in shell; libuv now checks that each pc
location assignment occurs once, then uses sed for those assignments and the
CMake prefix correction. Its generated dependency lists remain unchanged. The
other 31 multiline Python layout blocks are moved to
`recipes/<name>/relocate-development.py`, invoked by build.sh through
`RECIPE_DIR`. Their parsed Python statements are unchanged. These remain
independent recipe-owned scripts, with no new common staging helper. The
bootstrap fingerprint includes the full recipe directory, including these files;
the seed manifest is unchanged.

Validation: all 31 extracted scripts retain the original parsed Python
statements after formatting. All 32 affected recipe definitions render for both
dirty/result variants, and shell/Python syntax checks pass. The existing 37
repository tests pass. Fresh local result-variant builds of libuv and c-ares
against run `39051401807`'s selfhost channel passed their complete installed
package tests (`DEVKIT_RUN_TESTS=0` skips unrelated build-tree suites). These
builds exercise both shell/sed metadata repair and rattler-build's `RECIPE_DIR`
call to a separate Python file. This organization-only change does not repeat a
full bootstrap locally.
