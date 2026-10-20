# Native private installation directories experiment

Status: implementation and local validation in progress on
`experiment/native-private-install-dirs`, branched from `eacc432e333b`. Recipes
are migrated; the current policy is documented in
[development-layout.md](development-layout.md).

## Intended layout

Keep the Conda environment root as the installation prefix and keep executable
installation in `bin`. Configure other supported installation directories under
`lib/devkit`: libraries in `lib/devkit/lib`, headers in versioned directories
under `lib/devkit/include`, data in `lib/devkit/share`, and private executables
including development query tools in `lib/devkit/libexec`.

Prefer upstream directory options so generated pkg-config and CMake metadata
already describes the installed paths. Where an interface is missing, patch the
source build/installation rules rather than rewriting installed metadata.
Runtime libraries move together with link-time interfaces; installed ELF RUNPATH
and layout checks must change with them. Do not change the authoritative seed
manifest for this experiment.

CMake's own modules/resources remain in public `share/cmake-3.31`. Its
`Modules/Platform/UnixPaths.cmake` infers a system search prefix from
`CMAKE_ROOT`; placing its resources under the private directory would make CMake
search that private prefix by default. Keep pkgconf's explicit host-default
search paths. Recipe builds opt into private development interfaces explicitly.

## Approved seed GNU / private LLVM runtime coexistence

Moving LLVM-libgcc into the private library directory removes its file collision
with seed GNU libgcc. The user approved testing coexistence on 2026-10-19:
remove the dirty `libgcc` metadata-only replacement, preserve GNU libgcc for
seed tools, and use private LLVM-libgcc for rebuilt tools through their RUNPATH.
Result/selfhost outputs must still contain no GNU libgcc package.

A loader search probe using the actual cached seed libstdc++ confirmed that
private LLVM-libgcc alone is invisible to its public-directory RPATH: the loader
falls back to host libgcc. Keeping seed GNU libgcc beside seed libstdc++ selects
the seed GNU library instead. This establishes search behavior only, not
complete mixed-process ABI compatibility. Both runtime implementations have the
same SONAME, so a process may reuse the implementation already loaded.

## Approved dirty SONAME transition

A separate probe copied the cached seed manifest's top-level runtime libraries
and Clang driver into a temporary prefix and ran `clang-23 --version` with
`LD_BIND_NOW=1`, without `LD_LIBRARY_PATH` or `LD_PRELOAD`:

1. Original seed layout: success.
2. Move all `libxml2.so*` entries into `lib/devkit/lib`, leaving seed GNU libgcc
   public: exit 127, `libxml2.so.16: cannot open shared object file`.
3. Add only `lib/libxml2.so.16 -> devkit/lib/libxml2.so.16`: success.

This models library search after dirty libraries replace their seed package
interfaces. It is not a build or a solve of the migrated recipes. Seed libLLVM
has a direct `DT_NEEDED` for `libxml2.so.16` and public-library RPATH entries;
keeping seed GNU libgcc does not make other private libraries discoverable.

Approved transition: dirty library packages retain public SONAME aliases for
seed runtime compatibility, while result/selfhost omit them. Do not expose
unversioned `.so` linker interfaces, headers, or pkg-config/CMake metadata.
Determine the aliases actually needed by the seed dependency closure, and check
that installed links and library loading remain valid across stages. GNU libgcc
stays public in seed; LLVM-libgcc stays private, without a competing public
`libgcc_s.so.1` alias. The user approved this transition on 2026-10-19.

## Local validation before CI

All 54 recipes render for both dirty/result variants (108 renders). The package
pipeline/audit suite passes 38 tests; the dependency graph suite passes 19
tests, including the real renderer, and graph audit reports no ordinary-package
cycles.

Actual Rattler builds and installed tests passed for gnuconfig, libuv, zlib,
c-ares, lzo, bzip2, lz4-c, rhash, expat, pkgconf and ncurses. These use a
temporary local bridge made from the last successful selfhost channel: its
existing Clang has the new explicit config path and a temporary RUNPATH
accepting both layouts. This validates representative install rules, metadata
and installed behavior; it does not establish that the new compiler bootstraps
itself.

LLVM-libgcc and libc++ were additionally built from the pinned LLVM sources
using that toolchain and installed in a fresh prefix. Runtime probes cover
versioned libgcc interfaces, dynamic loading, glibc backtrace, libc++
exceptions, threads and filesystem; both probes and the completed-prefix
ELF/layout audit pass. libc++ modules use their native private module-directory
option.

Local builds exposed CMake's CACHE PATH normalization for LLVM-libgcc's relative
library-directory option; pass it as a typed STRING. ncurses needs explicit
separate narrow/wide native header directories, a matching helper include path,
and corrected terminfo compatibility-link generation because upstream assumes
libdir is prefix/lib. The source patch described below replaces the initial
post-install link removal.

The llvm-config helper patch applies to the pinned LLVM source, and the main
LLVM/Clang CMake configuration completes using temporary dependency links.
Generated install rules put llvm-config in private libexec with its own relative
RUNPATH; installed LLVM exports infer the environment root and private include,
library and CMake paths; Clang's resource libdir is private. Full compiler
compilation, all three bootstrap generations, installed relocation/discovery
checks and the remaining packages must still be verified by CI.

The CI revision planner requires every package selected by the global packaging
change to receive a new build number, including the imported sysroot. Its build
number is incremented without changing its layout or imported contents.

## OpenSSL includedir option trial

OpenSSL now carries `recipes/openssl/patches/includedir-option.patch`. The patch
adds `--includedir` to Configure, updates Unix header install/uninstall rules,
and passes the configured header path to the existing metadata generator. The
pkg-config and CMake templates themselves need no patch. The recipe supplies
`lib/devkit/include/openssl-${OPENSSL_VERSION}` and no longer moves headers or
rewrites installed metadata; its 24-line relocation script is removed.

Validation used the SHA256-verified pinned OpenSSL 3.5.9 release and host
Clang 18. Default, relative and absolute includedir configurations generated
correct pkg-config/CMake paths. The relative-directory configuration built and
installed successfully, including DESTDIR installation and uninstallation.
Separate pkg-config and CMake config-mode consumers compiled and ran; ldd
confirmed both loaded the newly installed private OpenSSL libraries.
Dirty/result recipe renders also pass. This validates the source patch and
install interface, not a fresh Conda build or full bootstrap; the local source
build omitted the upstream test suite.

The patch is longer than the removed metadata script, but centralizes the
installation decision in upstream's build machinery and avoids matching the text
of generated exports. Its TODO records that it should be proposed upstream;
Windows/VMS installation rules are outside this initial Unix trial.

## Applying native options and source patches to remaining recipes

The OpenSSL approach is now applied throughout the remaining development-layout
exceptions. All nine recipe-local `relocate-development.py` files are removed.
The authoritative seed and recipe feature selections remain unchanged.

| Recipe      | Build-system interface or source correction                                                                                        |
| ----------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| bzip2       | Independent `BINDIR`, `LIBDIR`, `INCLUDEDIR`, `MANDIR`; relative executable aliases                                                |
| curl        | `configbindir` for curl-config; `CURL_CONFIG_CC` for its consumer compiler command                                                 |
| libxml2     | `configbindir` for xml2-config                                                                                                     |
| PCRE2       | `PCRE2_CONFIG_INSTALL_DIR`; generated helper/pc includedir honors GNUInstallDirs, including absolute paths                         |
| krb5        | `KRB5_CONFIG_BINDIR` independent of client programs                                                                                |
| ncurses     | `CONFIG_BINDIR`; native configured header subdir; configured libdir-relative terminfo link; existing `--disable-pkg-ldflags`       |
| ICU         | `ICU_CONFIG_BINDIR`, `ICU_CONFIG_*` consumer settings and helper prefix depth; separate native generation of installed pkgdata.inc |
| Expat       | Autotools CMake exports derive relative include paths from configured libdir/includedir                                            |
| LZO         | pkg-config exports both supported header include styles                                                                            |
| LLVM-libgcc | Existing `COMPILER_RT_INSTALL_LIBRARY_DIR` installs CRT objects directly                                                           |

Each new source patch records an upstreaming TODO. Generated curl configure uses
Autoconf 2.71 and Makefile.in uses Automake 1.16.5; libxml2 Makefile.in uses
Automake 1.18.1. Both ICU configure patches are regenerated with Autoconf 2.72,
replacing the previous manually synchronized generated-script hunk. All release
patch chains apply with zero fuzz. Native development helpers retain upstream
configured absolute prefixes, which Conda's recorded text-prefix substitution
updates when installing into another environment. They no longer reconstruct all
paths by rewriting installed script text.

Additional local validation of this iteration:

- SHA256-verified pinned releases build/install with host Clang 18 for bzip2,
  LZO, PCRE2, Expat, ncurses (narrow and wide) and ICU. Expat's installed CMake
  export compiles/runs a consumer. PCRE2's generated helper and pc files use the
  configured versioned header directory rather than its upstream hardcoded
  `prefix/include`. The recipe test now also checks Expat with a CMake consumer.
- curl, libxml2 and krb5 configure successfully and their real installation
  targets install development helpers independently of public programs. These
  checks do not build the complete libraries.
- ncurses helper/pc dependency lists retain tinfo; two successive mode installs
  preserve the private relative `lib/terminfo -> ../share/terminfo` link. For
  this host-source check only, the terminfo directory is specified explicitly to
  avoid host ncurses discovery choosing `/usr/share/terminfo`.
- ICU builds with a marker in build-only compiler flags: the build configuration
  retains it, while installed pkgdata.inc and consumer settings do not. Its
  installed icu-config prefix detection works at its private helper depth.
- Six installed development helpers still report correct prefixes/includes after
  copying their trees and modeling Conda text-prefix replacement. This is a
  text-relocation check, not a fresh Conda installation.
- All 108 dirty/result recipe renders and the 38 pipeline/audit plus 19 graph
  tests pass. LLVM CRT placement is checked against the pinned upstream
  `add_compiler_rt_runtime`/`get_compiler_rt_install_dir` source; a complete
  LLVM build has not been repeated for this option-only change.

Host-source checks use host dependencies and may omit optional features/test
suites; they do not change recipe feature options. This iteration has not run a
fresh Conda package build or the full three-generation bootstrap. CI must still
verify the packaged toolchain, installed behavior and environment relocation.

## CI follow-up: Perl module directories

Run 39156299195 reached Perl in dirty, then failed its package-content check:
Config.pm was installed under public `lib/perl5` instead of the private tree.
Perl Configure's `installstyle` is a style selector, not an arbitrary relative
path. Its `*lib/perl5*` branch silently reduces the supplied value to the normal
`lib/perl5` layout.

Use the supported `privlib` and `sitelib` directory overrides explicitly, with
the ordinary `installstyle=lib/perl5` selector. Supply the documented `.../../`
interpreter-relative prefix, not an absolute environment path: Perl's INSTALL
explains that only paths starting with `.../` participate in
`userelocatableinc`. Configure derives matching architecture-specific and
install directories from these roots. No installed-file moves or new source
patch are needed. Perl's build number is incremented for the corrected layout.

Validation uses the SHA256-verified Perl 5.44.0 release, both recipe patches,
host Clang and the recipe's separate consumer Config generation/install path.
The complete interpreter builds and installs successfully. Config.pm is in the
private versioned architecture directory, and no public `lib/perl5` tree is
created. Core and XS modules (Config, POSIX, Socket, Storable, Test::More) load
both before and after renaming the complete installation directory, without
PERL5LIB/PERLLIB or loader overrides. Relocated @INC points only to the new
private module directories. Both dirty/result recipe renders pass. This is a
host-source validation, not a fresh Conda bootstrap.

## CI follow-up: libarchive GNUInstallDirs coverage

Run 39162367760 passed Perl and OpenSSL, then failed libarchive's
package-content check: the CMake build still installed archive.h/archive_entry.h
in public `include`. Including GNUInstallDirs in the project did not make its
literal installation paths respect the recipe options.

The recipe now patches the source header and manpage installation rules to use
`CMAKE_INSTALL_INCLUDEDIR` and `CMAKE_INSTALL_MANDIR`. Its pkg-config generator
also uses the configured libdir/includedir, handling relative and absolute
overrides while preserving the generated dependency lists. No installed-file
moves or metadata rewrites are added. The patch has an upstreaming TODO; the
package build number and private manpage content assertions are updated.

Local validation uses the SHA256-verified pinned libarchive 3.8.9 source and
host Clang/dependencies, with LZO from the previous local source build. The
library and all four tools build/install successfully. Shared and static
pkg-config consumers compile and complete the recipe's native LZO tar write/read
probe. Headers, pc metadata and manpages use the private directories; no public
include/manpage tree is created. The source patch applies with zero fuzz and
both dirty/result recipe renders pass. The temporary build disables the upstream
suite; the recipe's feature/test settings remain unchanged.

The later CMake recipes libssh2, jsoncpp and cppdap were also checked against
their pinned SHA256-verified source archives and existing patches. All three
build/install locally and put headers plus pc/CMake metadata in their configured
private directories. Temporary jsoncpp static objects use PIC as in the real
recipe; cppdap's temporary build omits its test-only GTest dependency. No recipe
changes were needed for those three packages. These host-source checks do not
replace the full packaged bootstrap and installed tests in CI.

## CI follow-up: curl GSS-API dependency root

Run 39182639892 passed the corrected libarchive installation and reached curl in
dirty. curl found the Kerberos headers but failed to link its GSS-API probe.
`--with-gssapi=${PREFIX}` made curl's `CURL_CHECK_PKGCONFIG` override the
recipe's `PKG_CONFIG_LIBDIR` inside its lookup subprocess, searching only the
public `${PREFIX}/lib/pkgconfig`. Its fallback also assumed a public
`bin/krb5-config` and ultimately tried `-lgssapi` instead of MIT's
`-lgssapi_krb5`.

Pass `${PREFIX}/lib/devkit` as the GSS-API installation root instead. curl now
checks the existing private pkg-config directory and obtains MIT's actual link
dependencies. Keep the separate versioned header directory option. No source
patch, installed-file rewriting or feature reduction is needed. Both curl output
build numbers are incremented.

Local validation builds/installs the pinned patched krb5 source with host Clang,
then configures the pinned patched curl against that private installation. The
original root reproduces the exact missing-GSS-API error; changing only the root
makes detection succeed. The resulting curl builds and reports GSS-API, Kerberos
and SPNEGO. This focused temporary curl build omits unrelated optional backends;
recipe features and its existing feature probe are unchanged. Both dirty/result
recipe renders and shell syntax/format checks pass. The full packaged bootstrap
remains CI's responsibility.

## CI follow-up: llvm-libgcc builtins installation

Run 39195039764 completed all dirty package builds, then failed the installed
compiler check when linking with the channel compiler configuration. The
compiler-rt builtins archive was missing from the expected private runtime
directory. Earlier in the log, llvm-libgcc installed it under
`lib/devkit/lib/<absolute-build-prefix>/lib/devkit/lib/linux`, and packaging
reported that the `libgcc.a` alias had no target in the package.

compiler-rt accepts an absolute `COMPILER_RT_INSTALL_LIBRARY_DIR`; its CRT
installation uses that destination directly. However, llvm-libgcc has its own
builtins installation rule, which strips only a leading literal `lib/` and
appends the remainder to `LLVM_LIBGCC_INSTALL_LIBRARY_DIR`. This assumed the
standard layout and incorrectly nested the recipe's absolute directory.

Patch llvm-libgcc's source to resolve both installation directories against
`CMAKE_INSTALL_PREFIX` and compute their relative path. Use that path for both
the builtins destination and its `libgcc.a` alias, so the alias remains
relocatable. Keep compiler-rt's native absolute directory override for CRT. The
patch records an upstreaming TODO. Add early build assertions for the archive,
its alias and both CRT objects, plus an explicit builtins archive
package-content assertion; increment the llvm-libgcc build number.

Validation uses the SHA256-verified LLVM 23.1.3 source archive and both recipe
patches (zero fuzz), with host Clang 18 and LLD. The actual llvm-libgcc/CRT
build and component installations pass with the recipe's private library paths.
The installed builtins archive and both CRT objects exist, and `libgcc.a`
resolves through the relative `linux/` alias. Using a resource-dir layout
matching the package, Clang links a probe calling compiler-rt's `__multi3`; that
probe runs successfully before and after renaming the whole installation prefix.
Four CMake path cases cover the standard layout and relative/absolute custom
directories. Both dirty/result recipe renders and shell syntax/format checks
pass. This focused host-source validation does not replace the packaged
three-generation bootstrap.

## CI follow-up: zlib installed-package test fixtures

Run 39207332785 passed dirty and result, then failed zlib's upstream CTest suite
in selfhost. The library built successfully. The `zlib_install` fixture
installed its temporary copy using the configured private libdir, but its
consumer configure commands supplied only the temporary installation prefix.
CMake does not infer `lib/devkit/lib/cmake/zlib` from that prefix, so the
positive CONFIG consumers failed to find ZLIB. The wrong-component test passed
for the same missing-package reason instead of checking component validation.

Patch the source test definitions to calculate the fixture's CONFIG directory
from `CMAKE_INSTALL_LIBDIR` (absolute or relative) and pass it as `ZLIB_DIR` to
the three installed-package configure tests. Two tests named `add_subdirectory`
also incorrectly configured the `findpackage_test` source; point them at their
already-generated add_subdirectory projects. Correct the coverage-summary
dependency's `zlib-coverage` typo to `zlib_coverage` so parallel CTest waits for
the coverage producer. Keep the earlier exclude-build fixture fix. Record an
upstreaming TODO and increment both zlib output build numbers. Library feature
options and installation rules are unchanged.

Using the SHA256-verified zlib 1.3.2 release and host Clang, the private layout
reproduces the exact original 10-of-18 failure. With both test patches applied
without fuzz, all 18 tests pass in parallel. Logs confirm the negative component
test finds the fixture's private CONFIG file and rejects the unsupported
component. Both dirty/result recipe renders and formatting checks pass. Full
selfhost and subsequent package checks remain CI's responsibility.

## CI follow-up: curl assertions still describing the old layout

Run 39237739210 completed dirty, result and selfhost. The installed-package test
job then stopped in curl: its script still required the unversioned library link
to target `../../libcurl.so.4.8.0`, an artifact of the previous post-install
layout. Native installation now places the real library and both aliases in the
same private libdir. The same test also compared pkg-config output against
unnormalized `../..` paths from the previous rewritten metadata.

Update the library-link expectation to `libcurl.so.4.8.0`. Assert that pkgconf
selects the private libcurl.pc, then compare its include/library flags with the
configured private directories under PREFIX. This retains the metadata and
consumer checks without requiring the old rewriting scheme. Both curl output
build numbers are incremented; library builds and source patches are unchanged.

Validation uses this run's downloaded selfhost channel, installed into a fresh
local prefix. All commands from the updated curl consumer test pass against the
actual CI-built binaries, including curl-config and pkgconf shared/static
consumers, feature checks, a file transfer and channel dependency resolution.
The remaining packaged tests (libcurl, jsoncpp, cppdap, ninja and cmake) also
pass locally through rattler-build. The other recipe tests were checked for the
same old link/pkg-config path assumptions; no further instances were found. Both
dirty/result recipe renders and formatting checks pass.

The complete `scripts/check-result.sh` stage check also passes against this
channel, including the compiler policy/runtime probes, glibc baseline, installed
file/ELF layout and basic tool execution.

## CI follow-up: standalone PCRE2 metadata assertions

Run 39286117833 passed bootstrap and its installed stage tests, then stopped in
the ordinary PCRE2 package's standalone `tests/development.sh`. The shared and
static CMake consumers passed for all widths; the final pkg-config assertion
still required the old rewritten `pkgconfig/../../lib` spelling. The previous
curl follow-up checked recipe YAML but missed this separately sourced script.

Update the standalone test to require the configured private library directory
and explicitly verify each width's private pc-file location. Audit all recipe
files, including separate build/test scripts, for the same relative metadata
assumptions. This also finds and corrects ripgrep's pre-Cargo PCRE2 link-flags
assertion. Increment both affected package build numbers. No library source,
feature or link behavior changes are required.

Validation performs a complete local PCRE2 recipe build using the CI run's
selfhost channel as the only dependency channel. Its four upstream CTests and
all installed-package tests pass, including layout/ELF checks, feature probes,
8/16/32-bit shared/static CMake consumers and private metadata assertions.
Install that newly built PCRE2 package with channel pkgconf in another prefix;
the actual pre-Cargo PCRE2 probe block from ripgrep's build script passes there.
The Rust application itself is not rebuilt for this assertion-only fix. Both
recipe renders, shell syntax/format checks and documentation formatting pass.
