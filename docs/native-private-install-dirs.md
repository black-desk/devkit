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
already describes the installed paths. Revisit recipe-local relocation only
where upstream has no suitable option. Runtime libraries move together with
link-time interfaces; installed ELF RUNPATH and layout checks must change with
them. Do not change the authoritative seed manifest for this experiment.

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
and removal of its obsolete public terminfo compatibility link after each
install because upstream assumes libdir is prefix/lib.

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
