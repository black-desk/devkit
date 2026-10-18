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
