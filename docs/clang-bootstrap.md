# Clang bootstrap experiment

This branch is migrating the Linux toolchain to Clang. The stage driver and
recipe scripts now use the expanded LLVM bootstrap closure. Full self-hosting
and all ordinary package builds are still under validation; do not treat this
branch as a verified release generation.

## Seed

`seed-packages.tsv` now pins 47 conda-forge archives (278,754,390 compressed
bytes) for Clang/LLVM tools 23.1.3, LLD 23.1.2, CMake 3.31.8, Ninja 1.13.2, Make
4.4.1, gnuconfig 2025.07.09, Perl 5.44.0, libxcrypt 4.4.38, and the glibc 2.28
development sysroot. The first C++ build uses GCC 16.2.0 development headers and
runtime libraries, but the seed contains no GCC/G++ compiler or GNU binutils.
These GNU runtime libraries are bootstrap inputs, not intended result-channel
dependencies.

LLD 23.1.2 is the currently published conda-forge release and declares support
for libllvm23 23.1.x; the seed solver selects libllvm23 23.1.3. This exact
combination is pinned in the manifest. Our own tools will use one source
version.

Fetch and verify this seed with:

```bash
pixi run bash scripts/fetch-seed.sh
pixi run check-seed
```

When changing manifests, move obsolete archives out of `channels/seed/` before
indexing it. A generated channel is not a second source of seed membership.

## Intended result

- Clang is the only C/C++ compiler provided by the channel.
- Channel builds explicitly select the Rocky glibc 2.28 sysroot, libc++,
  libc++abi, and llvm-libgcc. LLVM's llvm-libgcc builds compiler-rt and
  libunwind together and exposes GCC-compatible runtime names and symbol
  versions.
- Installed Clang defaults to host development interfaces; the channel's own
  headers, libraries, and linker must not silently become default inputs.
- Rust recipes retain the upstream rustup-managed toolchain. Only Rust recipe
  build invocations of upstream tools use an absolute, local `LD_PRELOAD` to
  select channel llvm-libgcc. Installed binaries use relocatable RUNPATH;
  separate package tests do not set either loader override variable.
- User-managed Rust toolchains keep upstream host requirements. The channel owns
  the compatibility of its packaged rustup and published applications.
- CMake/Ninja are initial seed tools and will be rebuilt before result-only
  bootstrap verification.

## Initial validation notes

The new seed has been resolved without a GCC compiler. The first
`recipes/llvm-libgcc` experiment uses only that seed and the dirty sysroot
variant. Build it with:

```bash
pixi run rattler-build build \
  --recipe recipes/llvm-libgcc/recipe.yaml \
  --target-platform linux-64 --no-config --channel-priority strict \
  --channel ./channels/seed --variant-config variants/dirty.yaml \
  --output-dir ./output/llvm-libgcc
```

The 44 seed archives have been downloaded and SHA-256/size verified. The offline
local-channel solve passes, and a seed-only temporary environment runs Clang,
CMake, and Ninja successfully. The experimental runtime recipe still declares
seed-only build dependencies and is not a final self-hosted recipe.

The initial llvm-libgcc build reached the shared-library link step. GNU ld.bfd
2.46.1 rejects the repeated `GCC_*` version nodes in upstream's generated
`gcc_s.ver` (`duplicate version tag`). A small independent link probe using the
same script confirms that upstream LLD 23.1.3 accepts those nodes and exports
the expected versioned symbol. This probe does not establish full runtime
compatibility.

The agreed direction is to use LLVM tools and LLD for all channel builds,
including the seed. The experiment explicitly selects `ld.lld`, `llvm-ar`,
`llvm-ranlib`, and `llvm-nm`, and uses Clang's integrated assembler.

llvm-libgcc now builds and passes its installed-package test. The test checks
GCC-versioned unwinding and integer builtins, stack traversal, and glibc
`backtrace` with exactly one loaded unwinder. Its only runtime dependency is
host glibc, and required glibc symbols are no newer than GLIBC_2.14.

The pinned upstream rustup 1.29.1 successfully installed Rust 1.98.1 using this
runtime in a temporary build-local loader environment. Rustc/cargo run, and
Clang/LLD link a Rust `catch_unwind` probe against it. That probe runs without
`LD_LIBRARY_PATH`, using `$ORIGIN/../lib` RUNPATH, and loads the LLVM unwinder
from its installation prefix.

The `recipes/libcxx` experiment built and passed its installed-package test,
combining libc++ and libc++abi while using the separately installed llvm-libgcc
via its gcc_s compatibility interface. It does not build a second unwinder.
Development headers are isolated under `include/libcxx-23.1.3/c++/v1`; CMake
export paths follow that layout. The test covers C++20 algorithms, exceptions,
threads, and filesystem operations, and verifies that the loaded C++ libraries
and sole unwinder come from the prefix. llvm-libgcc also now supplies
compiler-rt crtbegin/crtend objects under `lib/linux` for the later removal of
seed GCC development files.

The next experiment is `recipes/clang`: a single provisional carrier builds
Clang, LLD, and LLVM binary tools from the same 23.1.3 source. It builds against
the local libc++ and llvm-libgcc, limits parallel compilation to eight jobs and
parallel linking to two jobs, and targets X86. Optional zlib, zstd, libxml2,
libedit, and terminal support are disabled in this first experiment to keep its
bootstrap closure small; this means compressed debug-section and those optional
integrations need separate review before finalizing the toolchain. The
compiler's configured default is host libstdc++ and `/usr/bin/ld`. Restricting
GCC discovery to `/usr` via `GCC_INSTALL_PREFIX` failed configuration: Clang 23
rejects this deprecated setting unless `USE_DEPRECATED_GCC_INSTALL_PREFIX=ON` is
explicitly selected. Upstream recommends configuration files with
`--gcc-install-dir` or `--gcc-triple`, and discourages `--gcc-toolchain`. The
default discovery policy is now implemented with installed configuration files,
as agreed: `bin/clang.cfg` and `bin/clang++.cfg` set `--gcc-toolchain=/usr` for
users. Channel recipes instead pass `--no-default-config` and explicitly load
`share/devkit/clang.cfg`. That configuration uses `<CFGDIR>`-relative paths to
select the local Rocky sysroot, LLD, libc++, compiler-rt, and libunwind, without
discovering GCC development installations. The configuration does not set the
output's RUNPATH; packaging scripts remain responsible for relocatable runtime
search paths. The seed-built compiler itself still uses explicit seed flags
until its installed configuration has been validated. An independent seed-Clang
probe has loaded this configuration with a temporary prefix containing the
channel runtimes and a linked seed sysroot/resource header tree. It compiled and
ran the C++20 runtime fixture without any GCC development-directory selection,
loading exactly the prefix's libc++, ABI, and LLVM unwinder. Its output uses
`$ORIGIN/../lib` RUNPATH supplied separately by the probe command. This verifies
configuration parsing and runtime selection; the installed locally built
compiler and Rocky sysroot still need verification.

A follow-up C probe exposed a runtime-policy gap: it explicitly opens channel
`libgcc_s.so.1`, then calls host glibc `backtrace`. With only executable
RUNPATH, glibc loads host `libgcc_s.so.1` as well, leaving two unwinders in the
process. The executable's RUNPATH does not govern glibc's indirect `dlopen`
search. Repeating the same probe with DT_RPATH (`--disable-new-dtags` and
`$ORIGIN/../lib`) passes with one channel unwinder and no loader override. The
earlier package runtime test used local `LD_LIBRARY_PATH`, so did not exercise
this installed-output behavior. This exposed the SONAME identity gap described
below; the chosen fix registers libgcc's identity rather than replacing RUNPATH
with old RPATH.

Upstream research confirms that the naming is intentional in the current
implementation, rather than introduced by this recipe:

- [LLVM issue #192891](https://github.com/llvm/llvm-project/issues/192891)
  reports llvm-libgcc not being registered by `ldconfig`. A commenter reproduces
  the issue and reports that a real ELF with SONAME `libgcc_s.so.1` is
  registered. This is a related naming problem with a different trigger from our
  `backtrace` probe; the issue is open and does not provide an accepted upstream
  fix.
- [LLVM PR #65455](https://github.com/llvm/llvm-project/pull/65455) is the
  merged refactor that reuses `unwind_shared`, combines compiler-rt builtins
  into it, and adds the libgcc symlinks. The resulting SONAME remains
  `libunwind.so.1`.
- The
  [official motivation](https://github.com/llvm/llvm-project/blob/main/llvm-libgcc/docs/LLVMLibgcc.md#motivation)
  explicitly identifies glibc's hardcoded libgcc `dlopen` and incompatible
  unwinder cross-talk as the problem llvm-libgcc is meant to solve. Its target
  audience is distribution maintainers replacing system libgcc; our private
  prefix alongside an unchanged host libgcc is a distinct deployment case.
- [hermetic-llvm PR #758](https://github.com/hermeticbuild/hermetic-llvm/pull/758)
  independently identifies the libunwind SONAME/NEEDED behavior and proposes a
  real libgcc_s output. It is open and unmerged; it also changes symbol-version
  targeting, so it is not a ready-made fix for our deployment.

No merged fix for our exact private-prefix/dlopen reproducer was identified in
this search. Next investigate a single canonical LLVM ELF advertising
`libgcc_s.so.1`, retaining aliases to that same object, rather than replacing
RUNPATH globally or installing separate copies of the unwinder.

The [initial design review D108416](https://reviews.llvm.org/D108416) and
refactor review do not identify a specific objection to using libgcc's SONAME.
They do emphasize checking exported symbols and their GCC versions, and avoiding
separately built unwinder implementations. Absence of an objection is not an
upstream endorsement of a SONAME change. Matching `libgcc_s.so.1` also means
that an already loaded GNU libgcc may satisfy a subsequent LLVM request, or that
the LLVM implementation must satisfy GNU-built libraries' requirements. Locally,
llvm-libgcc exports GCC version nodes through GCC_7.0.0 but lacks host nodes
GCC_4.7.0, GCC_12.0.0, GCC_13.0.0, and GCC_14.0.0. This does not show our
current probes failing, but rules out treating it as an unconditional
replacement for every host libgcc dependency. Existing binaries referring to
`libunwind.so.1` also need an alias to the same canonical ELF after any rename.

A temporary copy with SONAME changed to `libgcc_s.so.1` passes the previously
failing RUNPATH-only glibc backtrace probe and the existing C++ fixture, without
`LD_LIBRARY_PATH`. The recipe now applies a small CMake patch that emits the
canonical shared ELF as `libgcc_s.so.1.0` with SONAME `libgcc_s.so.1`, and
installs the libunwind names as symlinks to it. Build number 3 has passed both
installed-package probes (absolute libgcc path and bare libunwind alias),
including the registered-name check and glibc backtrace, without loader
overrides. The fixture uses DT_RUNPATH and a test-local `runtime-lib` symlink
pointing to the tested installation. Rattler-Build's automatic relinking
converted the installed library's initial RUNPATH to RPATH. Runtime recipes now
preserve CMake's explicit `$ORIGIN` RUNPATH by disabling binary relinking, and
tests inspect the final dynamic tag. llvm-libgcc build 3 passes this additional
check. Static archives and text metadata retain the ordinary packaging checks
and prefix handling. With that temporary copy explicitly selected by absolute
`LD_PRELOAD`, upstream rustc/cargo 1.98.1 start successfully without
`LD_LIBRARY_PATH`; loader traces show only the selected LLVM unwinder.
`rustup run 1.98.1 rustc --version` also passes. This establishes a possible
build-local alternative to broad library search overrides, not complete Rust
recipe validation. Preload must stay scoped to Rust recipe build invocations of
upstream tools and their subprocesses, and depends on the matching libgcc
SONAME. The separate package-test process does not inherit build-script
variables. Installed-output tests use RUNPATH with both loader override
variables removed.

The rustup repack now declares llvm-libgcc as its runtime dependency and adds
`$ORIGIN/../..` RUNPATH to the real binary under `lib/rustup/1.29.1/`. Its
independent package test clears loader overrides and checks that libgcc resolves
under the package prefix. patchelf is explicitly listed as a Pixi packaging
tool, not a target-channel or seed dependency. Downloaded Rust toolchains are
still unmodified and will use build-local preload in Rust recipes; that does not
replace installed rustup's own runtime search path. An additional probe used the
built runtime packages, the seed Clang/LLD, and upstream Rust 1.98.1 to compile
a `catch_unwind` program with build-local preload. The output records NEEDED
`libgcc_s.so.1` and `$ORIGIN/../lib` RUNPATH, and runs successfully after both
loader override variables are cleared.

`recipes/ninja` has also been added with seed/channel compiler variants, local
libc++ dependencies, explicit RUNPATH, and a build-executor package test. It
uses bundled generated parsers and does not discover a host re2c installation.
Its seed-built package passes its version, RUNPATH, build-execution, and
incremental no-op tests. llvm-libgcc, libcxx, and Ninja now render result-stage
dependencies on channel Clang, with no seed GCC development requirements; actual
result-stage builds remain to be tested.

Graph tooling recognizes the new recipes' sysroot variants while retaining the
old names for baseline rendering. It also supports an explicit
`retired-packages.json` list when retiring GCC outputs: listed outputs must be
absent, unlisted deletions still fail, and retired edges do not enter the new
schedule. Changing that manifest selects a full build. The GCC, G++, GNU
binutils, and libstdcxx outputs have now been retired explicitly, and the
expanded LLVM closure passes graph audit. The first Clang carrier has passed
installed default-policy and explicit channel-policy checks. Clang self-hosting
and complete recipe migration remain pending; the current carrier includes
Clang, LLVM tools, and LLD together.

After installing the experimental Clang with its local runtime dependencies, run
`bash scripts/check-clang-policy.sh INSTALL_PREFIX` on a host with GCC
development files. It compiles and runs a C++20 exception probe without loader
or header overrides, checks `/usr` GCC discovery and `/usr/bin/ld`, rejects
channel headers/libraries in the default output, and checks that Clang itself
loads channel libc++. This is a host integration check, not a portable package
test that assumes every machine has development headers installed.

Rebuilt experimental runtime packages use build number 3: reusing the same
archive name after changing its contents left stale local Conda cache entries in
the first Clang attempt. The private libc++ link directory now includes the
versioned shared-library entries referenced by its linker script.

The first carrier was installed with locally rebuilt libcxx, llvm-libgcc, and
Rocky sysroot packages in a fresh environment without GCC or its development
packages. Both `scripts/check-clang-policy.sh` and
`scripts/check-clang-channel.sh` passed: default C++ programs use host GCC
headers and host libstdc++, while explicitly configured channel programs use
channel libc++ and llvm-libgcc. The compiler itself uses channel libc++.

The ongoing recipe migration introduces `share/devkit/build-env.sh` for explicit
native builds, `rust-env.sh` for scoped upstream Rust invocations, and
`finalize-elf.py` to set relative DT_RUNPATH on newly installed ELF files. The
finalizer excludes installed host dependency files. Automatic binary relocation
is disabled for these recipes because it converts RUNPATH to RPATH. Other prefix
relocation remains enabled. Bootstrap recipes copy these helper sources so the
seed stage does not need an already packaged channel compiler.

The dirty stage keeps conda-forge compiler tools, CMake, and Ninja in the build
prefix, including their GNU runtime dependencies. Channel C++ headers and
runtimes are separate host inputs. Channel Clang must not be installed into that
same seed build prefix: the GNU and LLVM packages own overlapping libgcc
filenames. The result stages will use rebuilt channel CMake and Ninja. Meson,
previously an implicit runner executable used by pkgconf, is now an explicit
Pixi orchestration dependency; Ninja is a recipe build dependency.

Make, Perl, pkgconf, OpenSSL, and CMake build scripts now select Clang with the
stage-specific sysroot. Native library and Rust application scripts have also
been updated, but these edits are not yet evidence of a successful whole-channel
build. The bootstrap driver and package-set checker now use the expanded LLVM
closure, and the old GNU compiler/runtime recipes have been retired. Full
bootstrap validation is still pending.

Clang build 1 passed its package tests and both installed integration checks. It
packages the shared build helpers and preserves DT_RUNPATH. Make passed its
complete upstream regression suite; pkgconf passed 29 upstream tests. Perl
passed its selected upstream tests and independent relocated-package tests using
Clang. The ELF finalizer handles read-only installed modules while preserving
their permission bits. Perl's installed XS metadata is normalized to channel
Clang/config paths even in a seed-built interpreter.

The first migrated Rust application, fd, passed its source build and package
tests using the upstream locked toolchain with scoped preload and channel Clang
linking. Rust recipes now also assert installed DT_RUNPATH and prefix-local
libgcc resolution with loader overrides removed. Full channel validation is
still pending.

Validation currently pauses for the first ordinary-library compatibility choice:
zlib 1.3.2 passes the complete zlib.map to a shared-library probe that only
defines hello(). LLD rejects absent versioned symbols, so configure silently
switches to static-only output and the consumer cannot find libz.so. The actual
compiler and shared linker work; this is a probe mismatch. No global linker
relaxation or zlib fix has been applied. The proposed local fix would adjust
only this configure probe while keeping real library version validation. Expat
and PCRE2 passed their Clang source builds and package tests.

OpenSSL passed its complete upstream test suite and installed consumer probe.
Its initial independent package-test setup failed because the manual command
omitted the local pkgconf channel; the full bootstrap order already supplies
pkgconf first. That package test and CMake build remain pending. The new fd
RUNPATH/runtime assertions were added after successful build 1; build 2 still
needs validation. Graph unit tests (18), graph audit, and the full affected
revision plan pass. No complete self-hosting or full-channel claim is made.

## Feature baseline and bootstrap closure correction

The maintainer requires preserving features enabled by conda-forge wherever
possible. Do not disable features merely to shrink the bootstrap closure. Audit
the corresponding conda-forge recipes/configurations and document any necessary
functional differences for discussion before implementing them. Existing
experimental binaries are not feature-complete release candidates.

The bootstrap includes seed tools' runtime dependencies. Its recipe ordering is
not a proof of self-hosting closure. The current seed LLVM tools and CMake,
along with several of their dependencies, require libzlib. The closure needs
revisiting; the current 13-package result check is provisional and does not
validate this new feature baseline.

Current reductions requiring review:

- The new Clang carrier disables zlib, zstd, libxml2, libedit, and terminfo,
  builds only the X86 backend, enables only the clang/lld projects, and disables
  LLVM bindings. These were experimental scope reductions, not established
  conda-forge-equivalent choices.
- The new llvm-libgcc recipe builds builtins, CRT objects, and the unwinder,
  while disabling compiler-rt sanitizers, XRay, libFuzzer, profiling, and ORC.
  Packaging those components elsewhere has not been implemented. In particular,
  shipping Clang without matching sanitizer/profile runtimes restricts users.
- New LLVM/libcxx/Ninja recipes disable upstream test builds; LLVM also omits
  examples/benchmarks. Test coverage and delivered runtime functionality must be
  audited separately.
- Pre-existing recipes also reduce features: CMake omits the Qt GUI and uses
  bundled libraries; OpenSSL disables zlib; PCRE2 omits 16/32-bit libraries;
  curl disables HTTP/2/3, multiple authentication/name-resolution backends, and
  compression integrations; Git omits Tcl/Tk, Python helpers, and gettext. These
  settings predate the Clang migration but still need baseline review.

LIBCXXABI_USE_LLVM_UNWINDER=OFF selects the external gcc_s interface supplied by
our LLVM unwinder; it does not mean LLVM unwinding support is disabled. No
recipe feature flags have been changed as part of this documentation update.

## zlib LLD workaround applied

The maintainer approved the recipe-local workaround used by merged
[NixOS/nixpkgs#307540](https://github.com/NixOS/nixpkgs/pull/307540).
`recipes/zlib/build.sh` appends `-Wl,--undefined-version` to its LDFLAGS for
configure and the package build. The channel compiler configuration is
unchanged. The TODO links the Nix PR and upstream issues
[zlib#960](https://github.com/madler/zlib/issues/960) and
[zlib#1318](https://github.com/madler/zlib/issues/1318), and records removal
when the shared-library probe is fixed upstream. No source patch is needed.

The Clang/LLD rebuild now detects shared-library support and passes zlib's
upstream tests, the installed-library consumer probe without loader overrides,
and all package tests. A fresh installation preserves SONAME `libz.so.1` and
relative DT_RUNPATH; exported compressBound, deflateBound, and crc32_combine
retain their ZLIB symbol versions. Reconstructing the broader bootstrap closure
and matching conda-forge's enabled features remain separate pending work.

## Expanded closure validation

The audit now reads build recipes embedded in the pinned seed packages, as well
as current conda-forge feedstocks. The pinned Clang enables zlib, zstd, libxml2,
RTTI, and default PIE. conda-forge LLVM disables libedit/terminfo too, so those
flags are not established feature regressions. The pinned CMake enables ccmake
and disables the Qt GUI; its dependencies include ncurses.

Bootstrap membership now includes zlib, zstd, and ncurses. zlib selects the seed
compiler/sysroot in dirty builds and channel Clang in result builds. zstd 1.5.7
preserves gzip CLI integration and adds pzstd; ncurses 6.6 builds both narrow
and wide-character libraries. Headers remain version-isolated. Their recipes and
revised closure are under validation, not a completed fixed point. Further LLVM
dependencies (including libxml2 and its ICU/iconv/lzma interfaces), CMake system
libraries, and compiler-rt user runtimes remain pending.

OpenSSL's independent package tests have now passed with the local pkgconf
channel supplied. No OpenSSL source change was required for that retry.

The updated zlib recipe passed its dirty-stage build and package tests using
seed Clang with the local Rocky sysroot. OpenSSL's independent package tests
also pass. The ncurses build currently stops at the formal libtinfo link: its
resulting.map includes symbols belonging to other ncurses components, which LLD
rejects as undefined versions. No workaround has yet been applied.

This is documented upstream in
https://lists.gnu.org/archive/html/bug-ncurses/2024-05/msg00086.html and
downstream in https://github.com/NixOS/nixpkgs/issues/310727. Nix implements a
recipe-local `-Wl,--undefined-version` workaround in
https://github.com/NixOS/nixpkgs/pull/309887; its current ncurses recipe still
uses that approach. The proposed resolution keeps the separate tinfo library,
narrow/wide APIs, and versioned symbols enabled, with a recipe-local TODO.
Validation pauses for discussion of this newly encountered package case. The
added zstd recipe has not yet been built.

The maintainer approved the ncurses recipe-local LLD workaround. Its build
script now appends `-Wl,--undefined-version`, with a TODO linking Nix PR
#309887, issue #310727, and the upstream ncurses mailing-list report. Split
tinfo, versioned symbols, and narrow/wide interfaces remain enabled. The rebuild
and initial zstd build are in progress; neither is yet a successful package
claim.

The subsequent ncurses build exposed missing `<new>` includes for
`std::bad_alloc` with libc++. A source patch adds the required includes, and the
recipe now declares the local pkgconf build dependency. The zstd shared CLI test
loaded the host's older libzstd because upstream forces install RPATH in the
build tree. A source patch enables CMake's build-tree RUNPATH instead. Source
fixes are maintained as recipe patches rather than sed substitutions. Both fixes
still require build and package-test validation.

The patched ncurses dirty-stage build and independent package tests now pass:
narrow/wide libraries, separate tinfo libraries, relocated terminfo lookup, and
DT_RUNPATH on all ten tested shared libraries. Loader overrides are unset. The
patched zstd playTests suite also passes; its remaining upstream tests are still
running.

The libiconv bootstrap recipe follows the seed's conda-forge 1.18 source and
glibc gets patch, retaining static libraries and extra encodings. Library-only
installation matches the forge libiconv package; headers are version-isolated.
It is added before Clang for the forthcoming libxml2 dependency. Its build is
not yet validated, and the expanded closure remains incomplete.

Libiconv's dirty-stage upstream tests and independent package tests pass. An
installed ncurses C++ binding probe also links and runs against channel libc++
and llvm-libgcc. That inspection exposed seed compiler flags in generated
pkg-config/config-script metadata and stale config-script include paths. Ncurses
build 1 normalizes that consumer metadata and adds package assertions; its
rebuild is pending. The bootstrap closure is still incomplete.

Liblzma 5.8.3 is added to the provisional bootstrap order using the seed
source/hash and upstream default codec/filter/threading features. The recipe
builds and tests XZ, then installs library/development files with isolated
headers. The build has not yet passed; ICU/libxml2 and further CMake runtime
dependencies still remain to be added.

Liblzma's dirty-stage source build, upstream tests and independent package tests
now pass. ICU 78's configure step requires Python to generate data build rules.
The current seed has no Python; the existing channel Python recipe repackages
python-build-standalone using uv, which would also pull Rust into the bootstrap
build graph. ICU work pauses for a decision on Python's closure membership
versus an explicitly allowed Pixi orchestration dependency. No implicit host
Python dependency has been introduced for ICU.

Ncurses build 1 now passes its dirty-stage build and independent package tests,
including generated consumer metadata checks and isolated header directory
lookup. Graph audit and the baseline-aware rebuild plan also pass after adding
libiconv/liblzma. Zstd playTests, fullbench and zstreamtest pass; the remaining
default fuzzer run is still pending. None of these dirty-stage results proves a
complete seed-free bootstrap closure yet.

## ICU without Python: source investigation and build probe

The earlier claim that ICU 78 requires Python for configuration was too broad.
ICU 78.3's configure.ac explicitly handles an empty PYTHON by writing empty
data/testdata rules.mk files. data/Makefile.in separately supports packaging the
prebuilt source/data/in/icudt78l.dat shipped in the official source tarball. See
https://github.com/unicode-org/icu/blob/release-78.3/icu4c/source/configure.ac
and
https://github.com/unicode-org/icu/blob/release-78.3/icu4c/source/data/Makefile.in.
The official data build-tool documentation also describes .dat archive priority:
https://unicode-org.github.io/icu/userguide/icu_data/buildtool.html.

An isolated research build used the existing channel Clang, system GNU Make, and
Autoconf's `ac_cv_prog_PYTHON=` cache override (with `PYTHON=`) to prevent
Python discovery. There is no dedicated --without-python option. Configure and
the full build passed, using the source tarball alone, without the extra
data.zip. Samples/extras/tests were disabled as in the forge recipe; this is not
yet a rattler-build recipe or a seed-free closure validation.

The official .dat is 33,107,232 bytes, SHA256
`d5cf2a40dccbe471781ec7af85693bff542ff12f0b670c9630c4e72d60714b8b`. Its complete
contents occur byte-for-byte in both the current seed's forge libicudata.so.78.3
and the newly built library. Thus this data input preserves the current seed
data, rather than reducing locales or encodings. A runtime probe, with
LD_LIBRARY_PATH/LD_PRELOAD/ICU_DATA unset, passed GB18030 conversion
availability, zh_CN collation and ar_EG date formatting; it enumerated 906
locales and 232 converters.

Python remains necessary for regenerating/customizing data from its text sources
and for the Python data-builder tests. Upstream's internal build INVOKE still
sets LD_LIBRARY_PATH; adapting that to the channel's RUNPATH policy remains part
of future recipe integration. No ICU recipe or seed change has been made by this
research. The Python closure decision can be avoided for ICU if the official
prebuilt data mode is selected.

The previously running zstd dirty-stage build has also completed successfully,
including all four upstream CTest suites and independent package tests.

### Clarification: automatic prebuilt-data mode versus Python test rules

Upstream deliberately supports source release tarballs with prebuilt data. PR
https://github.com/unicode-org/icu/pull/502 (merged 2019-03-02) and
https://github.com/unicode-org/icu/pull/503 (merged 2019-03-04) implement the
automatic skip of Python production data rules when data/locales/root.txt is
absent. PR https://github.com/unicode-org/icu/pull/570 additionally handles
empty test-data rules when Python is unavailable. No special configure option is
needed to select the source tarball's prebuilt production data.

A second configure probe used normal Python discovery, without the cache
override, with --disable-tests. It succeeded and logged both:
`Not rebuilding data/rules.mk, assuming prebuilt data in data/in` and
`Spawning Python to generate test/testdata/rules.mk...`. ICU 78.3 and the
checked upstream main configure.ac do not guard that latter invocation with the
tests setting. Thus the cache override is a way to force the existing
no-interpreter branch, not a documented ICU prebuilt-data switch. A cleaner
prospective recipe patch would make test-data rule generation honor
--disable-tests, retaining automatic prebuilt production data handling. That
patch has not been implemented or validated, and no ICU recipe is added yet.

The patch is now available at
`recipes/icu/patches/skip-disabled-test-data.patch`. It wraps only test-data
rule generation in `if test "$tests" = true`, otherwise creating an empty
test/testdata/rules.mk. Both configure.ac and the distributed configure script
are patched, so applying it does not introduce an Autoconf build dependency.
Production data selection and Python discovery remain unchanged; no cache
override is needed.

The patch applied to the official 78.3 source with zero fuzz. Two configure
probes passed: --disable-tests with an invocation sentinel interpreter (which
would fail if called) never invoked it and created empty test rules;
--enable-tests with the real Python generated populated test rules as before.
The patched configure also passed shell syntax validation. These validate
configuration behavior, not a new complete ICU package build. No ICU recipe has
yet been added to the bootstrap order.

ICU's test-data patch now includes a FIXME documenting that configure was
manually synchronized and should be regenerated with GNU Autoconf 2.72, as
identified in the release script header (`cd source && autoconf`). The new ICU
recipe joins the provisional closure using official prebuilt data and the patch;
no Python/Autoconf seed dependency is added. Its dirty build is not yet
validated. Internal tools get build-tree RUNPATH, with Make's
INVOKE/PKGDATA_INVOKE/INSTALLED_INVOKE loader overrides cleared. Installed
headers and consumer metadata are normalized, and a data/runtime package probe
runs without loader environment variables.

ICU's dirty-stage build and independent data/runtime package tests now pass
without Python invocation or ICU's loader-environment Make wrappers. The libxml2
2.15.4 recipe uses the official GNOME release tarball with shipped configure
(SHA256 verified against GNOME's published checksum), avoiding Autoconf build
tools. It retains ICU/iconv/zlib/legacy/Schematron and thread-local-storage
features. FTP and LZMA were removed by upstream in 2.14/2.15; the corresponding
old forge arguments do not provide those features in the same seed version. No
extra feature reduction is introduced here. Libtool -no-install supplies direct
build-tree executables for RUNPATH-based source testing. Libxml2 build/package
verification is still pending.

Libxml2's dirty-stage upstream tests and independent package tests now pass,
with ICU, zlib and Schematron reported enabled. The source tests used direct ELF
executables through Libtool -no-install. The Clang build 2 recipe restores
forge's compression/XML libraries, RTTI, default Linux PIE, backtraces/dump,
Intel JIT events and stable LLVM target backends. The rebuilt dependency
libraries are explicit host inputs; forge Clang/CMake remain dirty-stage build
tools. Build 2 is not validated yet. Compiler-rt runtime features and the
remaining CMake closure are still pending.

The feature-restored Clang build stopped during dependency solving: seed Clang's
unconstrained libxml2 dependency selected the newly built channel libxml2, which
pulls channel zlib into BUILD_PREFIX. Forge CMake's libzlib constrains zlib to
its forge build and rejects that mixed environment. No Clang compilation
occurred. A temporary render/solve experiment outside the repository explicitly
channel-qualified the seed icu/liblzma/libxml2/ncurses/ zstd build dependencies.
It solved successfully: BUILD_PREFIX selected forge libraries from seed, while
HOST_PREFIX selected the rebuilt channel libraries. The temporary recipe uses
checkout-specific absolute seed URLs and is not a production solution. That
temporary mixed-generation approach has been superseded by the strict
previous-stage-only decision below. It will not be adopted in the bootstrap
driver; package features and strict channel priority remain unchanged.

The agreed stage boundary now applies to both build and host dependencies: dirty
reads seed only, result reads dirty only, and self-hosting reads the completed
result only. Each recipe build skips package tests; a stage archive manifest
drives deferred recipe tests with only the completed stage channel. Channel-wide
checks run after those tests. Self-host output is staged in result-rebuild and
promoted only after success, keeping its input unchanged. Existing dirty recipes
requiring local llvm-libgcc/libcxx are not yet compatible with the seed-only
rule; dependency solving must be repaired before a full run.

Stage-driver verification: an isolated temporary fixture exercised all three
stages with two mock recipes, checking single input channels, deferred test
order, skipped in-build package tests, successful promotion, and stopping on a
package test failure. Graph tests pass (18 tests). A real seed-only libcxx
render/solve preflight fails in HOST_PREFIX: no candidate for
`llvm-libgcc ==23.1.3` exists in seed. This is a recipe/seed transition problem,
not a build or package-test failure; no full bootstrap was started.

## Dependency-source priority research

Implementation of dirty seed binding is paused pending a supported approach. The
experimental `prepare-dirty-recipe.py` and its driver integration are not an
accepted production solution and have not been used for a full bootstrap.

Source inspection of rattler-build v0.75.0 and rattler_solve 9.0.0 shows:

- `ChannelPriority` has Strict, Disabled, and Flexible variants. Strict excludes
  lower-priority candidates by package name; it does not inherit the depending
  package's channel rank. The installed rattler-build CLI accepts only strict
  and disabled, even though the solver library also has Flexible.
- Resolvo's `get_dependencies` parses each record's dependency MatchSpecs
  without adding a lower bound on channel rank from the parent record.
- rattler-build passes the same channel list to build and host solves.
- The solver has a dependency-overrides API, but rattler-build's solve wrapper
  leaves it at its default. It is not a current recipe/CLI solution.

A synthetic three-channel render/solve experiment confirmed that strict mode
selects a tool explicitly from channel 2 and its unqualified library dependency
from channel 1. No archives or actual build were needed. Thus existing strict
priority does not enforce the proposed rule that dependencies of a channel-2
package may only come from channels 2 or 3. Sources and experiment logs were
kept under /tmp; no downloaded source is committed.

## Restoring compatibility meta outputs

The source-binding experiment has been removed. Dirty now uses the ordinary
strict `dirty > seed` order for both build and host; result and self-host retain
previous-generation-only inputs. This supersedes the earlier seed-only dirty
rule and the proposal to bind the seed tool closure separately. Package tests
remain deferred until the complete stage is available.

The channel keeps complete upstream installations in content-bearing packages.
Conda-forge split names are supplied through metadata-only interfaces where
needed, rather than splitting ownership of the installed files. The zlib recipe
now emits `zlib` (all content) and noarch `libzlib` (an exact dependency on the
sibling zlib output). Selecting our libzlib avoids the forge runtime package's
`zlib ==1.3.2 *_3` constraint. The channel checker explicitly installs both
interfaces. Seed manifest contents are unchanged.

Validation of the zlib compatibility outputs:

- zlib build 3 and its libzlib meta output built successfully; both independent
  recipe package tests passed. Installed libzlib metadata has an empty file
  list.
- An environment containing seed CMake and our zlib/libzlib configured and built
  a small C project, and created/listed a gzip-compressed archive. Loader debug
  output confirmed CMake initialized our prefix's `libz.so.1`, without loader
  path/preload overrides.
- The original Clang recipe now renders/solves successfully against a temporary
  channel assembled from earlier dirty artifacts plus the new zlib outputs,
  followed by seed, with strict priority. BUILD_PREFIX selects seed Clang/CMake
  and dirty zlib/libzlib/libxml2. No source-binding recipe rewriting is used.
- All 18 dependency-graph tests and the graph audit pass. This is not yet a
  completed dirty generation or a full three-stage bootstrap validation.

The full seed closure is now recorded in
[bootstrap-closure.md](bootstrap-closure.md). It includes all 44 manifest
members, dependency paths, carrier mappings, missing recipes and functional
gaps. Bzip2 has been added and validated as a leaf package. The inventory also
records actual file collisions in the mixed Clang build solve; these must be
resolved before claiming that the successful solve makes the dirty compiler
build safe to proceed. Expanded closure size is accepted; final package
functionality is to be preserved.

## Dirty-only libgcc compatibility experiment

LLVM-libgcc build 4 now has a dirty-only noarch `libgcc` meta output. The driver
uses `scripts/seed-libgcc-variant.py` to read the exact libgcc archive identity
from `seed-packages.tsv` and verified local repodata, checking the seed
libstdcxx pin before producing a variant config. The version/build currently are
`16.2.0 ha9f2e26_7`. This deliberately preserves a seed dependency identity, not
a claim of GNU implementation or complete GCC 16 ABI coverage. The meta owns no
files and depends exactly on its sibling LLVM-libgcc. Result rendering omits it.
Missing seed variants are rejected when building the meta output.

A fresh, isolated-cache installation of seed Clang/CMake/Ninja/LLD/LLVM tools,
GNU libstdcxx and development headers plus the two new outputs succeeded. Its
installed file manifests give LLVM-libgcc sole ownership of libgcc_s.so.1;
libgcc's manifest is empty. All tested seed tool version commands succeeded with
immediate dynamic binding and no LD_PRELOAD/LD_LIBRARY_PATH.

The focused GNU-libstdc++ probe then failed at LLD linking: six GNU-versioned
symbols are required by libstdcxx but exported unversioned by LLVM-libgcc:
`__trunctfxf2`, `__getf2`, `__eqtf2`, `__extendxftf2`, `__unordtf2`, `__letf2`,
all at `GCC_4.3.0`. No linker relaxation was applied. The reproducible probe is
`scripts/check-seed-llvm-runtime.sh`, with sources under scripts/tests/.

For an additional diagnostic only, a reference binary/DSO was linked against GNU
libgcc from a separate seed environment, then executed with GNU libstdcxx and
LLVM-libgcc from the target prefix via embedded RUNPATH (no loader path or
preload override). It passed 1,000 throw/catch operations with destructor
checks, nested exceptions, async exception transfer, DSO exception propagation,
pthread cancellation cleanup, and long-double conversion/formatting. Loaded
library enumeration confirmed a single LLVM libgcc_s and prefix-owned GNU
libstdcxx. This supports using LLVM-libgcc for these existing seed binaries; it
does not resolve the linker-visible versioning defect or prove full ABI
compatibility. Fixing/exporting the six versions remains a decision for the next
step; no runtime implementation patch was applied during this verification.

Follow-up diagnostic: adding `-Wl,--allow-shlib-undefined` to the same probe
link, retaining `--unwindlib=libgcc` and the target prefix's LLVM library, lets
LLD link successfully. The full runtime probe then passes with LD_BIND_NOW=1 and
without loader path/preload overrides. GNU libgcc was not used at link time in
this diagnostic. The initial diagnostic used only /tmp. Following approval,
LLVM-libgcc build 5 adds the relaxation only when bootstrapping with seed GNU
libstdc++; the adjacent TODO records the missing versions and removal condition.
Final libc++ builds retain the normal strict linker check. The rebuilt carrier
and focused mixed-tool runtime probes passed.

The distinction is supported by glibc 2.39's elf/dl-lookup.c `check_match`: a
non-hidden versioned reference may fall back to an unversioned global default
definition. LLD's executable link normally disallows unresolved references in
input shared libraries. `--allow-shlib-undefined` suppresses that shared-library
check broadly; it does not add GCC symbol versions, disable unresolved object
symbol errors, or establish complete ABI compatibility. It is distinct from
`--undefined-version`, which concerns names listed in a version script.

## Latest closure verification

The dirty-only libgcc meta and libxml2-16 meta have been validated together in a
fresh mixed-tool environment: the carrier libraries have sole file ownership and
both compatibility outputs are file-free. Libxml2 build 1 and its meta passed
independent package tests. The approved dirty-only LLD relaxation is now
documented next to its flags in LLVM-libgcc build 5; final libc++ links retain
strict checks.

Libuv 1.52.1 build 0 passed its full source suite and independent archive tests.
Four earlier failures came from local transparent proxy DNS/TCP interception.
Running tests/builds with `systemd-run --user --slice cgtproxy-direct.slice -P`
passed without source patches, feature reduction, or skipped tests. This is a
local execution workaround; recipes and GitHub CI do not require cgtproxy.

RHash 1.4.6 build 0 passed upstream static/shared library and full CLI suites
and independent archive checks using seed Clang/LLVM tools. Its optional OpenSSL
backend is disabled in the exact seed conda-forge recipe too. The channel
preserves that baseline and adds static library/pkg-config installation with
isolated headers. Bootstrap ordering and expected-package checks include both
new carriers. Eight seed-closure library recipes remain missing; these
individual successes do not establish complete dirty/result/self-host builds.

C-ares, libev and libedit now have verified leaf recipes and are scheduled in
bootstrap order; see bootstrap-closure.md for feature coverage. Keyutils now
also builds and passes independent package tests after the approved patch
removes two nonexistent symbols from the upstream version script. The patch
includes a TODO to upstream it. All 41 public function exports and symbol
versions match the seed. No new broad linker relaxation has been introduced.

Libpsl now has a validated ICU/built-in-data recipe, including all eight
upstream library/CLI tests and independent archive checks. Libssh2 is drafted
with seed-equivalent OpenSSL/zlib features but awaits OpenSSL prerequisite
validation. Kerberos configuration exposed a build-time gettext/msgfmt
requirement for translations; the approved provider has now been added to
bootstrap rather than silently omitting translation catalogs.

The OpenSSL prerequisite validation completed: dirty-mode OpenSSL 3.5.9 build 1
passed its upstream suite (347 files, 4,518 tests) and independent package tests
using channel Perl and seed Clang/LLVM tools. Libssh2's draft has not yet been
built; the gettext prerequisite is resolved by the new validated carrier.

The approved gettext prerequisite is complete: seed pins gettext-tools 0.25.1
h0e23cf9_2 and the offline 45-package solve passes without extra runtime
archives. Gettext build 0 and its file-free gettext-tools compatibility output
passed Clang/libc++ compilation, the complete upstream suite (988 passes, 137
upstream optional skips, no failures/errors), and independent package checks. A
fresh alias-only environment contains no GNU runtime packages and has one msgfmt
owner, gettext.

The check invocation avoids forwarding Libtool's -no-install flag into
Autopoint's plain C fixtures. Local Go test module downloads require the proxy
cgroup; direct Google-hosted module access timed out and rattler filters caller
cache environment variables. The successful complete run used cgtproxy-proxy
outside the Codex sandbox; recipes do not disable Go or exempt the test.

Kerberos 1.22.2 has passed Clang builds and independent archive tests with both
seed msgfmt and the self-built gettext-tools alias. Catalog files are present,
and self-built msgfmt generates a German catalog byte-identical to the seed
output. Bootstrap ordering, variants, seed checks and final expected-package
checks include these new inputs/outputs. Remaining closure members and the full
dirty/result/self-host rebuild remain unverified.

Libssh2 1.11.1 now builds with seed Clang/LLD against own OpenSSL and zlib,
retaining the seed's shared-only configuration and compression support. Its
standalone CTest check and independent package probe pass; the latter enables
session compression before checking the supported algorithm list. Docker/SSHD
integration tests are explicitly deferred until OpenSSH is packaged, as agreed;
no host SSH server or Docker dependency is introduced. Libssh2 is scheduled
after OpenSSL. This does not validate a complete bootstrap generation.

Libnghttp2 1.68.1 build 0 passed seed-Clang/libc++ compilation against own
OpenSSL, zlib, c-ares and libev. It retains nghttp, nghttpd, nghttpx, h2load and
shipped man pages, matching the seed native application coverage and shared-only
library configuration. All three upstream test executables pass (main,
failmalloc, nghttpx-unittest); independent archive tests verify HTTP/2 client
preface/SETTINGS serialization, tool startup, contents and relative RUNPATH
without loader overrides. Configure's C++20 probe clears CXXFLAGS, so libc++
selection is retained on the CXX command for those probes. Python is optional
for this release build and only regenerates Sphinx API docs; the Automake
interpreter-absent branch is selected explicitly instead of finding a caller's
Python. No seed package was added. Stage ordering, variants and expected-package
checks include libnghttp2. Full generation validation remains pending.

Curl 8.22.0 build 2 restores the exact seed libcurl native feature baseline:
HTTP/2, SSH/SCP/SFTP, MIT Kerberos/GSSAPI/SPNEGO, PSL, zstd, WebSocket protocols
and the built-in manual. It builds with seed Clang/LLD against own OpenSSL,
zlib, zstd, krb5, libssh2, libnghttp2 and libpsl. Both shared and static libcurl
consumer probes pass, as do independent carrier and file-free libcurl meta
tests. Static libcurl consumers link the channel's shared backend libraries;
this does not promise a completely static executable. The retained curl-config
helper and pkg-config metadata publish exact dependency library paths. Public
curl headers do not expose backend types, so private backend package
requirements are represented by exact link paths without importing backend
header directories.

A fresh own-channel-only libcurl/pkgconf installation selects 19 packages, has
no GNU libgcc/libstdcxx/libgomp packages and assigns libcurl.so.4 solely to
curl. With LD_LIBRARY_PATH/LD_PRELOAD unset, curl's resolved ELF dependencies
use host glibc and channel libraries for everything else. Package tests check
features/protocols, shared/static consumers, local file transfer, relocatable
helpers/pkg-config metadata, certificate bundle and library resolution; the full
upstream network/integration suite is not run (the exact seed recipe also omits
make test). The built-in manual was verified separately. No seed archive was
added. Stage ordering, variants, graph and expected-package checks include
curl/libcurl. Full dirty/result/self-host validation remains pending.

Expat 2.8.5 build 2 is now scheduled with dirty/result compiler variants and a
file-free exact-sibling libexpat alias. Unlike the old recipe, examples and
upstream tests are enabled, matching the seed baseline. Clang compilation, make
check and both independent archive tests pass. Xmlwf accepts valid XML and
rejects malformed XML; package checks cover the consumer probe, isolated
headers, pkg-config, CMake metadata, relative RUNPATH and shipped xmlwf manual.
The release provides its man page, and upstream explicitly supports installing
it without DocBook regeneration; no documentation tool was added to seed.
Generated CMake metadata is corrected with an asserted replacement after
installation, without editing source through sed. Libc++/LLVM-libgcc host inputs
support the configure-time C++ feature checks; their run exports are ignored
because the installed library and xmlwf do not use them. Both ELF files have no
C++/libgcc runtime dependency, and the carrier's sole runtime requirement is
host glibc. The alias owns no files. Bootstrap variants, graph and final
expected package sets include expat/libexpat. Full three-stage validation
remains pending; CMake and expanded LLVM are the next work.

## Approved external CMake dependencies

CMake will use channel-provided libarchive, jsoncpp and cppdap instead of its
bundled copies. Libarchive will retain the conda-forge GPL variant's LZO
support, as explicitly approved; LZO and LZ4 are new closure members. LZO is
GPL-2.0-or-later. Most libarchive backends already exist: zlib, bzip2, liblzma,
zstd, OpenSSL and libxml2. Jsoncpp needs only the C++ runtime; cppdap can use
the same jsoncpp backend as CMake's bundled cppdap. LZO, LZ4 and libarchive have
passed Clang builds and independent archive tests. Jsoncpp/cppdap recipes now
use Clang and channel libc++; upstream and packaged tests have passed. These new
carriers are not included in the seed manifest. Stage order and package checks
include LZO, LZ4 and libarchive. No conda-forge runtime archive is needed merely
to compile a new library from source; seed changes remain deliberate and depend
on actual seed-tool requirements.

LZO 2.10, LZ4 1.10.0 (carrier lz4-c), and libarchive 3.8.9 are now scheduled.
LZO preserves shared/static libraries, isolated headers and its installed
upstream examples; all five upstream CTest cases and the independent
compression/decompression probe pass. LZ4 retains shared/static libraries and
all four CLI interfaces; conda-forge's seven basic corpus tests and independent
API/CLI roundtrips pass. The LZ4 carrier records both the BSD library and GPL
CLI licenses and packages their license texts.

Libarchive uses the exact conda-forge source archive and upstream CMake build to
avoid adding autoreconf tools. It explicitly enables the approved LZO backend
alongside LZ4, zlib, bzip2, liblzma, zstd, OpenSSL and libxml2. CMake requires
iconv for libxml2, unlike the forge Autotools configuration, so the existing
channel libiconv is enabled as well; this does not add a new closure member.
Expat and Nettle stay disabled as in forge. A source patch makes header
installation honor GNUInstallDirs; generated pkg-config metadata exports
version-isolated headers and exact library paths. All selected backend macros
are checked before building so dependencies cannot silently disappear.

The full libarchive CTest run has 1,019 entries: 908 pass, 111 upstream optional
skips, no failures. Independent package tests cover tools, headers, relative
RUNPATH and a native LZO-compressed tar write/read roundtrip; requiring
ARCHIVE_OK on filter setup rules out the external lzop fallback. The source
includes its libb2 implementation, so no libb2 runtime package is needed. The
seed manifest remains unchanged. New recipes use the common stage variants and
are included in ordering, dependency graph and final expected-package checks.
Jsoncpp/cppdap and the external-library CMake build have since passed their
tests, along with full dirty/result/self-host validation.

A fresh own-channel-only libarchive installation selects 14 packages, including
LZO/LZ4, without GNU libgcc/libstdcxx/libgomp. With loader overrides unset,
bsdtar and libarchive.so resolve host glibc and channel libraries for all other
dependencies. LZ4's packaged library/CLI license texts were also checked.

### External CMake libraries: current implementation

Jsoncpp 1.9.8 and cppdap 1.65.0 now build with channel libc++ and pass their
upstream tests and packaged API probes. Cppdap uses precisely CMake 3.31.8's
upstream revision c69444ed76f7468b232ac4f989cb8f2bdc100185. Its GoogleTest
source is built only in a temporary test prefix, never added to the seed or
runtime channel. Shared SONAME/versioning and installed JsonCpp discovery
patches have upstream TODOs. Both libraries also ship static archives.

CMake now configures with previous-stage CMake/Ninja, external channel
libarchive/jsoncpp/cppdap/curl/expat/libuv/rhash and ncurses/libform for ccmake.
CMake discovery is confined to the host prefix and glibc sysroot, and isolated
header paths are specified explicitly. Configuration assertions reject a silent
loss of ccmake, debugger or external library support. The upstream
CTestTestParallel/DOWNLOAD test subset matches the forge validation baseline.
The expanded CMake build and its forge-baseline upstream tests have passed;
packaged consumer/runtime checks have also passed.

CMake 3.31.8 needs a small compatibility backport for curl 8.22.0:
`cmCTestCurl::HTTPProxyType` is a `long`, matching CURLOPT_PROXYTYPE and current
upstream CMake, rather than `curl_proxytype`. This preserves HTTP/SOCKS proxy
functionality with the newer long-valued CURLPROXY constants.

### Compiler-rt placement

The early llvm-libgcc carrier remains responsible for builtins, CRT objects and
unwinding. The Clang carrier builds the user-facing compiler-rt runtimes after
LLVM installation, using the already available channel libc++/libc++abi:
sanitisers, XRay, libFuzzer, instrumentation profiling, ORC, memory profiling
and context profiling. They share `lib/linux` through Clang's resource-directory
symlink; headers live under `lib/clang/23/include`. This avoids adding a libc++
dependency to llvm-libgcc (and thus a bootstrap dependency cycle), and avoids
duplicate builtins/CRT ownership. This expanded build remains pending
validation; required runtime archives are asserted before packaging.

Compiler-rt's private libFuzzer libc++ build needs clean base compiler flags:
its wrapper headers must not `include_next` the channel-installed libc++
wrappers. A small TODO-marked upstream patch allows separate internal libc++
C/C++ flags, retaining upstream defaults unless explicitly overridden. The
recipe passes a glibc sysroot and disables default Clang configs for that
private build; the other runtime libraries keep channel libc++ headers. This
retains libFuzzer's upstream hermetic static libc++ implementation.

The CMake curses build needs both the isolated ncurses header root and its
`ncurses` subdirectory, just like ncurses' exported pkg-config flags. The local
DOWNLOAD bad-hostname test must run in the transparent-proxy bypass cgroup to
observe the expected DNS failure; no test is disabled in recipes. The canonical
sysroot plus dirty-stage seed-triplet alias has passed packaged tests.

The external-library CMake package tests pass, including compiling/running a
channel-libc++ consumer and checking ccmake's ncurses linkage. A fresh
channel-only runtime installation has no GNU runtime packages; an ldd audit of
cmake/ctest/cpack/ccmake and jsoncpp/cppdap finds host glibc and channel
libraries exclusively. The result-variant graph audit renders all 58 package
nodes with 392 dependency edges and no non-bootstrap dependency cycles.

The standalone compiler-rt build has passed using the channel Clang/libc++
compiler, including the hermetic private libc++ build for libFuzzer. ASan/UBSan
C++ exception/container execution passes; intentional heap-buffer overflow is
reported by ASan; libFuzzer executes ten runs; instrumented profiling produces a
nonempty profraw; XRay reports an instrumented function and patches it. These
checks use no loader overrides. LeakSanitizer requires an unsandboxed local run
because the Codex sandbox blocks its process/thread inspection; no runtime
feature or recipe test is disabled for this local limitation.

The complete all-backend LLVM/Clang carrier build remains in progress. The
source recipe adds equivalent deferred runtime probes for completed stage
testing; standalone runtime success is not yet a completed bootstrap fixed point
or verification of that full carrier.

Ninja now enables its upstream NinjaTest suite with the exact GoogleTest 1.16.0
source/hash from upstream's FetchContent declaration. The test source is fetched
as a declared source input and all implicit downloads are disabled; GoogleTest
installation is disabled, so it adds no runtime/seed package. Ninja uses the
shared channel build flags and relocatable RUNPATH finalizer. This test-enabled
Ninja rebuild and its packaged consumer tests have passed.

The same header isolation applies to result/self-host libc++ builds themselves:
they bypass the recipe clang.cfg's installed-libc++ include path and use a clean
explicit sysroot/compiler-rt configuration with GCC discovery disabled. The
project supplies its own C++ headers (`-nostdinc++`), while the normal channel
recipe configuration remains unchanged. This prevents the old stage's C wrapper
headers from entering include_next during a libc++ rebuild. The focused
own-channel rebuild and packaged libc++/ABI/LLVM-unwinder tests have passed
before the full stage run.

### Expanded compiler carrier: focused validation

The complete all-backend LLVM/Clang/LLD and compiler-rt carrier compiled and
installed successfully. Its first package content check retained an ORC filename
from the render made at build start (`libclang_rt.orc`); the actual upstream
filename is `liborc_rt-x86_64.a`, now corrected in the recipe. An independently
installed carrier passes host-default compiler policy and
channel-libc++/LLVM-unwinder checks, and its ASan/UBSan, libFuzzer, profiling
and XRay probes pass without loader overrides. ELF audits of Clang, LLD, libLLVM
and shared ASan find channel dependencies plus host glibc only; their required
glibc symbol versions are <= 2.28. No GNU runtime package is selected.

The clean full bootstrap is the next validation: it must rebuild from current
recipes, including corrected content checks and deferred runtime probes, then
validate completed dirty/result/result-rebuild stages. The temporary incremental
channel and the focused checks are not a completed self-hosting fixed point.
Local build invocations use the previously verified cgroup bypass for
libuv/CMake network error tests and the proxy cgroup for gettext's Go module
downloads; these machine-specific wrappers are kept in /tmp.

The clean bootstrap initially stopped during cleanup of old gettext Go-module
caches, whose directories are read-only. Cleanup now walks generated trees
without entering src_cache, grants write permission only to generated
directories, unlinks files/symlinks without following symlinks, and removes
empty generated directories. Source cache contents and even their empty
directories remain intact; generated hardlinked files are not chmodded. A
focused check covers read-only directories, cache preservation, external
symlinks and repeated cleanup. This also removes the old find -depth/-prune
combination, which traversed source caches despite intending to preserve them.
The affected-package CI path uses the same cleanup helper, so ordinary recipe
rebuilds also preserve source caches and handle read-only generated directories.

While the clean bootstrap runs, PCRE2 10.49 build 1 has been rebuilt against the
temporary channel's expanded Clang and canonical sysroot. Its upstream tests and
packaged metadata/config-helper tests pass. Rustup 1.29.1 build 2 and
rust-toolchain-lock 1.98.1 build 1 also pass their package tests against that
channel; Rustup's RUNPATH resolves LLVM-libgcc without loader overrides. These
focused checks do not substitute for completed-stage validation. FD 10.5.0 build
2 also passes a fresh source build and all packaged tests with Rust 1.98.1,
scoped LLVM-libgcc preload for downloaded tools and channel Clang linking. With
loader overrides removed, the installed executable has DT_RUNPATH and resolves
libgcc_s.so.1 from its installed channel prefix. Just 1.58.0 build 1 passes the
same fresh source-build and packaged RUNPATH/ LLVM-libgcc checks, including
command execution and installed completions. Ripgrep 15.2.0 build 1 passes its
source build and packaged search/completion/ RUNPATH tests with the same runtime
policy. The official Go 1.27.1 repack also passes its package tests, including
compiling and running a CGO-disabled program with isolated Go caches. Gopls
0.23.0 build 1 passes its module verification, source build and package tests
against the official Go package.

Difftastic's bundled jemalloc configure uses `-Werror` for its strerror_r probe.
Clang 23 diagnoses absolute-path `-fuse-ld=` as deprecated, causing that
unrelated probe to fail. All channel linker selections now use the supported
absolute-path `--ld-path=` option, including the explicit config, shared build
helper and toolchain build scripts. No jemalloc feature or compiler diagnostic
is disabled. Validation against the newly packaged helper/config is pending
until the running Clang build completes.

Git 2.56.0 compiles with channel Clang and passes its functional and external
library tests. Its final runtime assertion incorrectly required a libgcc
dependency even for a pure C executable that needs no unwinder. That check now
verifies prefix-local libgcc only when present; the RUNPATH check remains
mandatory. A fresh rebuild with this correction passes all package tests,
including Git operations, external-library resolution and the RUNPATH check.

Replacing only the generated temporary Difftastic environment's helper and
config with the corrected `--ld-path` versions lets the complete source build
finish, including jemalloc. This diagnostic rerun confirms the cause but is not
a fresh packaged-artifact validation; that remains pending. Lazygit 0.65.1 build
2 passes its Go source build and package tests against the newly verified Git
package.

The affected-build planner treats the common output-cleanup helper and
completed-stage test runner as global bootstrap inputs. Changes to either
therefore trigger a complete generation rebuild instead of silently skipping
package validation.

Readelf symbol-version audits of the focused ordinary artifacts find maximum
GLIBC requirements of 2.14 for PCRE2, 2.17 for Rustup, and 2.28 for FD, Just,
Ripgrep and Git. Go's 22 actual tool executables, Gopls and Lazygit are static
and require no versioned glibc symbols. Go also ships 46 ELF parser-test
fixtures under source `testdata` directories, some with GLIBC_2.34; those are
inputs to DWARF/ELF parsers rather than runtime programs and remain preserved in
the repack. They are excluded only from the runtime compatibility audit.

The clean dirty-stage Clang artifact has now been generated successfully,
including compiler-rt and relocatable deferred test probes. Inspection confirms
its shipped config and build helper both use `--ld-path`. Difftastic 0.71.0 has
been freshly rebuilt against this artifact and passes all package tests,
including diff output, RUNPATH and prefix-local LLVM-libgcc resolution. This
supersedes the earlier diagnostic-only retry; completed-stage Clang tests and
the full self-hosting fixed point are still pending. The Difftastic executable's
maximum required GLIBC symbol version is 2.28. UV 0.12.22 build 1 also passes
its fresh source build and all package tests, including offline
package/tool-management smoke tests and prefix-local LLVM-libgcc resolution for
both uv and uvx without loader overrides. Python 3.14.8 build 1 passes its
official-distribution repack and all package tests using this UV package,
including relocated sysconfig paths, native runtime modules,
virtualenv/ensurepip and isolated UV tool integration. B4 0.16.0 build 1 passes
its pinned-wheel/source repack and all package tests using these UV/Python
packages and the verified Git package. Further ELF audits find maximum GLIBC
requirements of 2.28 for UV, 2.17 for Python and 2.25 for B4; none has a GNU
libstdc++ dynamic dependency. Python and B4 also have no direct libgcc_s
dependency; UV's required interface resolves to the channel LLVM implementation
as verified by its package tests.

Yazi 26.9.1 build 1 completes its source build. The initial integrated test
solve cached the temporary channel index before Python was published, so it
reported no Python candidate. A fresh standalone invocation after all test
dependencies were published passes every packaged test, including the PTY
terminal interaction and both executables' RUNPATH/LLVM-libgcc checks. Their
maximum GLIBC requirement is 2.28, with no GNU libstdc++ dependency. All 15
ordinary recipes now have successful focused build/repack and package tests;
these use the temporary incremental channel, not the final self-hosted result.

The clean dirty generation has completed all 38 recipe builds, all deferred
package tests and its stage-only closure/policy checks. Its installed tool
interface selects 44 packages without GNU runtime packages. ASan/UBSan,
intentional heap-overflow detection, fuzzer, profiling and XRay probes pass. The
default-host-library policy and explicit channel-libc++/LLVM unwinder policy
both pass. The result stage is running against completed dirty only; LLVM-libgcc
and libc++ have already rebuilt successfully without seed input. Complete result
and immutable-result self-host validation remain pending. All 15 ordinary
artifacts additionally pass their complete independent package tests using a new
local channel containing the completed dirty generation and those ordinary
artifacts only. This validates their runtime interfaces against a complete
bootstrap generation rather than the older incremental collection; no seed
fallback is available in that test channel.

The first result-stage Zstd build passes all four upstream tests, including the
full 30,000-round fuzzer (858.65 seconds), then stops compiling pzstd. The
shared helper appended HOST_PREFIX libc++ headers after clang.cfg already
selected BUILD_PREFIX libc++ headers. Duplicate C wrapper headers intercept
include_next, hiding libc string/errno declarations. Later native stages now use
the config's single libc++ header root; both prefixes select the same libc++
package from the same completed input generation. Dirty seed builds still
explicitly select HOST_PREFIX libc++ headers, since the seed compiler has GNU
standard-library development support. Host library linking stays explicitly
directed at PREFIX. The Clang build applies the same correction.
Result/self-host validation is not complete; the failed Zstd recipe must be
retried before the result stage can continue. With only that header-root
correction applied in the failed generated environment, pzstd compiles and
passes a compression/decompression roundtrip. The local continuation uses a
temporary /tmp runner with the canonical build flags, recipe order and
stage-only input channels. It verifies that the reused result prefix exactly
matches its published archive manifest, then freshly rebuilds Zstd (including
all tests) and the rest of result. It will independently test result, rebuild
every recipe into result-rebuild using immutable result, and test/check before
promotion. Fresh package caches separate build/test roles, and a SHA-256
snapshot additionally checks input immutability. This machine-local continuation
is not committed and does not change the standard fresh-bootstrap entry point.

Compiler-rt explicitly receives LLVM nm/objcopy and LLD paths. Its libFuzzer
partial archive merge also uses the private compile flags and configured LLD,
rather than invoking a bare compiler that can reload a default config and choose
host GNU ld. This is part of the same TODO-marked private-libc++ toolchain patch
and preserves the bundled hermetic libc++ behavior.

The explicit LLVM-tool/LLD private-libc++ merge patch has also passed a fresh
standalone compiler-rt build with the expanded channel Clang. This check uses a
fresh CMake build tree (changing a cached compiler can discard the original
install/target flags); the bootstrap always creates fresh trees.

The clean dirty-stage zstd build has completed its full default CTest suite:
fullbench, zstreamtest, playTests and the 30,000-round fuzzer all pass. The
fuzzer takes about 15 minutes on this machine; no fuzzer time limit or test
exemption was introduced. The stage continues through the expanded closure.

The resumed result-stage Zstd build also passes the full upstream suite and
pzstd build. Result then reaches liblzma, exposing a GNU libtool issue: its
shared-library link allowlist drops `--config=`, `--no-default-config` and
`--ld-path=`, so compilation and executable links use the channel sysroot but
shared links reload the compiler's default host policy. liblzma consequently
requires host GLIBC_2.32/2.34 symbols that the channel's 2.28 sysroot cannot
resolve. GNU libtool master has the same missing flag support.

Recipes using bundled libtool now carry source patches retaining Clang's
explicit config, GCC-discovery, linker and runtime selection flags. Each patch
has a TODO to submit the support upstream. The same patches apply to dirty and
later stages; no loader environment or compatibility-check relaxation is used. A
first liblzma build exited successfully, but log inspection found that the
initial patch used a quoting helper absent in newer generated libtool scripts.
That result is not accepted as validation. Patches now reuse each bundled
version's existing quoting and command-append implementation; the affected
builds are rerunning with actual shared-link command inspection. Previously
published result libev, lzo, libedit and libiconv will be rebuilt before
continuation, despite their existing GLIBC symbol requirements remaining within
2.28. Stage validation now checks every installed ELF against the glibc 2.28
baseline, so a shared link silently escaping the sysroot is caught even when the
individual recipe's executable tests happen to run on a newer host. Result and
self-host completion remain pending.

The corrected libtool patch passes a fresh liblzma build and upstream tests. Its
actual shared-library link retains `--no-default-config`, `--config=` and
`--ld-path=`. The installed ELF has `$ORIGIN` RUNPATH and requires at most
GLIBC_2.17; the former GLIBC_2.32/2.34 requirements are gone. Previously
published libev, libedit and libiconv have also been rebuilt, and result has
continued to ICU. LZO uses CMake and needs no libtool patch; its redundant local
retry passed as well. PCRE2, the ordinary Autotools consumer, is being rebuilt
with the same libtool fix.

PCRE2's corrected build, upstream tests and independent package tests all pass,
using only the completed dirty generation plus ordinary channel artifacts. Its
four installed ELF files pass the glibc baseline audit. Rechecking the completed
dirty stage with the new audit also passes for all 677 installed ELF files,
alongside both compiler/library policy checks. Format checks (25 C/C++ files,
Python and Markdown/YAML/JSON), shell syntax checks, 18 graph tests and the
graph audit pass after these changes.

The corrected result continuation has completed gettext (including its full
upstream tests) and libxml2. Result Clang is now rebuilding against completed
dirty with the single libc++ header root. Completion of result and the
immutable-result self-host generation is still required.

Result Clang has since completed its full build, runtime-probe compilation and
packaging. The next recipe, Perl, fails Configure: its Linux hints invoke
`/usr/bin/gcc` for library discovery and pick host Berkeley DB/libcrypt paths,
while the actual Clang link remains inside the channel's 2.28 sysroot. The dirty
build's explicit sysroot flags prevented that host probe from succeeding; its
packaged Config confirms `d_crypt='undef'`. Passing the existing Perl tests
therefore did not establish conda-forge feature parity.

The current
[forge Perl recipe](https://github.com/conda-forge/perl-feedstock/blob/main/recipe/meta.yaml)
declares libxcrypt as a Linux host dependency. Berkeley DB is not a declared
dependency, and forge's build comments explicitly avoid discovering host DBM
libraries. The
[forge libxcrypt recipe](https://github.com/conda-forge/libxcrypt-feedstock/blob/main/recipe/recipe.yaml)
states that it obtains Perl from yum to avoid the Perl/libxcrypt dependency
cycle. Upstream libxcrypt uses Perl both during configure and to generate
headers and its symbol map; this is not just regeneration of its release
configure.

Proposed handling, pending maintainer discussion: import forge Perl and
libxcrypt into the seed, add libxcrypt to the bootstrap closure before Perl, use
the previous generation's Perl to build libxcrypt, then build the current
generation's Perl against that libxcrypt. Dirty falls back to seed Perl; result
uses completed dirty Perl; self-host uses immutable completed result Perl.
Explicit Perl library-discovery paths should exclude host Berkeley DB without
disabling the forge-supported crypt interface. Seed and closure manifests have
not yet been changed for this proposal.

Independent dirty-mode checks of the final libtool allowlist patches use
temporary output directories and do not publish into the completed dirty input
channel. All nine recipes (libev, libedit, libiconv, liblzma, libpsl, gettext,
libxml2, libnghttp2 and curl) pass their builds and independent package tests.
Their 51 installed ELF files pass the glibc 2.28 baseline audit and have no
direct GNU libstdc++ dependency. The main bootstrap is stopped at Perl, and
complete result/self-host validation is not yet achieved.

## Perl/libxcrypt bootstrap cycle accepted

The maintainer approved adding forge Perl 5.44.0 and libxcrypt 4.4.38 to the
seed (47 archives). The bootstrap now has 39 recipes and a 45-package installed
closure, including libxcrypt before Perl. Libxcrypt uses the completed input
generation's Perl: seed for dirty, dirty for result, and immutable result for
self-host. Its configuration matches forge's main output (strong,glibc hashes,
no obsolete ABI, no failure tokens, shared library). Headers are
version-isolated and libraries retain relative RUNPATH. The libtool Clang driver
policy patch is also applied to this recipe.

Perl explicitly limits library discovery to the channel prefix and glibc
sysroot, retains crypt via libxcrypt, and tests both its Config feature flag and
actual SHA-512 crypt operation. Curl retains Perl for generating installed man
pages; a Perl-less build is supported upstream but would omit those documents.
The previously completed dirty generation lacked Perl crypt support, so it is
not a valid input to the updated result generation. A fresh complete bootstrap
will be required after targeted validation; previous stage validation remains
historical evidence, not validation of the expanded closure.

Targeted validation of the new libxcrypt recipe passes all 43 upstream test
cases (33 pass, 10 skip because the forge-matching hash/API configuration
excludes their algorithms), plus its independent installed-package test. LLD
exposed five compatibility-only entries left in the upstream version script when
obsolete APIs are disabled. A source patch passes config.h to the symbol map
generator and omits only those disabled symbols; the default generator behavior
is preserved for callers without this argument. TODO upstream; the paired
Makefile.in edit records automake 1.16.5 regeneration.

Perl also needs explicit cppstdin/cpprun policy: Configure otherwise probes
include directories with plain Clang -E before its normal ccflags are applied,
thereby entering the compiler's host-default mode. Its supported command-line
overrides now carry the same channel compiler options as compilation. The
result-mode diagnostic configure detects crypt and crypt_r and excludes host
Berkeley DB; the complete build and clean generations are still pending.

The result-mode Perl diagnostic now builds and passes its selected upstream
harness (471 assertions) and independent installed-package tests, including
Config d_crypt=define and an actual SHA-512 crypt call without loader overrides.
The symbol-map patch is separately checked in both modes: obsolete enabled
produces byte-identical output to the original generator; obsolete disabled
omits the five compatibility-only entries and retains current crypt APIs. Graph
validation passes 18 tests, renders 59 outputs/400 local edges and reports no
non-bootstrap cycles. The fresh 47-package seed solves offline. A clean full
bootstrap is now starting; these targeted diagnostics do not replace complete
stage validation.

## CI experiment and compiler parallelism

The maintainer approved opening a draft PR to exercise the existing package
workflow. The initial experiment used a single six-hour job. The later
[package CI stage split](package-ci.md) supersedes that orchestration; package
features and final upstream test workloads remain unchanged. PR builds do not
publish packages. Actions job logs are available through GitHub API or
`gh run view RUN_ID --log`, so no log artifact is needed for inspection.

Clang compilation and its compiler-rt build now use the runner's full CPU_COUNT
instead of capping it at eight. LLVM's separate link pool remains limited to two
concurrent links. An already running Ninja invocation keeps its original
parallelism; subsequent recipe builds pick up this change. The local clean
bootstrap remains in progress, and the draft PR must not present the result or
self-host generation as validated.

The first PR run passes formatting and dependency-graph tests. Its generic clean
check rejects unified-diff blank context markers as trailing whitespace. Eight
patches now use empty context lines; trailing blank context is omitted with
matching hunk counts where necessary. Applying the original and corrected
patches to pinned sources produces byte-identical files, and local clean passes.
The shared generic action also requires Conventional Commits, so the experiment
commit message is normalized before re-running CI. Package builds are still
running, and the local dirty stage has completed Clang and libxcrypt and is now
building/testing Perl.

The subsequent CI run completes every dirty recipe and its independent stage
package tests. It fails the closure name comparison because the runner's locale
sorts libxcrypt before libxml2, whereas the manually maintained expected list
uses C collation. Captured expected/actual lists contain the same 45 package
names. Both lists are now normalized with LC_ALL=C sort -u before comparison;
strict channel provenance and compiler/runtime audits remain in place. Local
bootstrap was cancelled at the maintainer's request and is not resumed. Result
and self-host validation remain pending the next CI run.

## Bootstrap test execution policy

Local and CI bootstrap now use the same policy: dirty and result skip upstream
suites and independent package tests; final self-hosting runs both. Every stage
still runs closure, compiler, runtime and glibc compatibility audits. Cheap
source smoke probes are retained. The final Zstd suite keeps all 30,000 fuzzer
rounds. Ordinary package builds and standalone recipe builds retain their tests.

Recipes explicitly read DEVKIT_RUN_TESTS through rattler-build's supported
script.env interface, defaulting to 1. Bootstrap supplies 0 for the first two
stages and 1 for result-rebuild. No stage variant or package hash is added.
Independent package tests run only after result-rebuild is complete, before
promotion. This reduces repeated suite execution without changing build features
or the final acceptance tests. Local bootstrap remains cancelled.

## Recipe-local build environments

The earlier build-env.sh, test-env.sh and rust-env.sh design is superseded.
Compiler/tool variables and build flags now live in each consuming recipe. The
three shared environment scripts are removed from the repository and the Clang
package. clang.cfg still owns the explicit channel compiler policy, and
finalize-elf.py remains the relocation utility; neither is an environment
script.

Each bootstrap recipe prepares its fresh seed build prefix with relative clang
and clang++ symlinks to clang-23 and clang++-23 before using the unversioned
drivers. This is an ordinary recipe build-script step after dependency
installation, with no reliance on rattler-build internals. No extra seed package
is introduced and seed-packages.tsv and downloaded archives remain unchanged.
Ordinary recipes only use the channel compiler and do not carry seed branches.
Seed compiler flags and libc++ header selection retain their existing behavior.

Recipes gate upstream suites directly on DEVKIT_RUN_TESTS (default 1),
validating 0/1 before building. Final-stage test workloads are unchanged. The
seven Rust recipes define their own scoped devkit_rustup function and linker
settings; preload remains limited to upstream Rust invocations. Updating the
seed GCC development layout, libc++ versioned headers or Rust linking policy
requires reviewing these recipe-local settings together. LLVM binary-tool path
declarations are expected to remain stable. The completed environment refactor
is included with the subsequent CI repair.

Local verification compares 74 recipe/mode environments against the previous
helper behavior, including seed driver symlink targets. All 27 upstream-suite
gates skip with 0 and execute with 1 or the default. All 91 recipe/variant
renderings, the 18 dependency-graph tests, revision planning, Bash syntax and
format/whitespace checks pass. This is configuration and orchestration
verification. Subsequent focused package builds are recorded below; the full
local bootstrap remains stopped.

## Default host development discovery

Channel CMake excludes its own installation prefix from implicit system-prefix
and PATH-derived package, library and header searches. Paths are canonicalized
so symlinks into that prefix are also excluded. Program searches retain PATH;
channel Clang, Ninja and other tools remain available. Explicit package roots,
package directories, CMAKE_PREFIX_PATH, hints and project installation prefixes
retain upstream behavior and can select channel development interfaces. Metadata
stays in its existing locations; recipes explicitly select their dependency
prefixes rather than relying on CMake's installation location.

Channel pkgconf uses upstream with-pkg-config-dir to search host /usr/local and
/usr metadata directories, including x86_64-linux-gnu and lib64 locations. On
Linux pkgconf does not derive these paths from PATH. PKG_CONFIG_LIBDIR replaces
the default directories and PKG_CONFIG_PATH adds explicit overrides. The system
include/library options only control flag filtering, not metadata discovery.
These changes affect development discovery, not tool runtime dependencies.

Focused validation compiles patched CMake 3.31.8 and pkgconf 3.0.7 from source.
Synthetic metadata tests cover default exclusion, symlinked PATH entries,
explicit prefix/environment overrides, retained program searches and searches
outside the tool prefix. Both recipes include these discovery checks as package
tests. Full bootstrap validation has not been repeated for this policy change.

The CI run on 4c2c0f933686 reached the result-stage libnghttp2 build and failed
because its CXX override added a host-prefix libc++ header tree alongside the
build-prefix tree selected by clang.cfg. libc++ include_next then skipped the
intended C headers, causing missing errno and math declarations. The recipe now
moves its existing CXXFLAGS policy onto CXX (configure temporarily clears
CXXFLAGS during its C++20 probe), retaining only one libc++ header tree. A
focused channel build passes the upstream and package suites.

Rust recipes obtain absolute RUSTC and RUSTDOC paths through rustup which after
installing the pinned toolchain. rustup run alone adds CARGO_HOME/bin to PATH,
which need not contain rustc shims in a fresh recipe environment. Cargo
therefore must not rely on a developer's host rustup installation. The existing
scoped llvm-libgcc preload still applies only to upstream Rust invocations.

## Independent CI stages

Package orchestration now uses a single frozen plan, three bootstrap build jobs,
a final package-test/smoke job and an ordinary-package job. bootstrap.sh
supports dirty/result/selfhost/test entry points; its all mode retains local
one-command bootstrap. Dirty/result keep their boundary checks, selfhost checks
solver closure after full upstream suites, and test performs independent package
tests and the full final policy/runtime/glibc checks. Stage manifests and
commit/plan-linked checksums travel with channel archives. Ordinary output is a
separate overlay; publication merges verified applicable artifacts. See
[package CI](package-ci.md) for skip conditions, file protocol and local
commands. No full local bootstrap is restarted to verify this orchestration
change.
