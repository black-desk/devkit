# Recipe review after libuv and RHash

Reviewed on 2026-10-17, continuing the maintainer's bootstrap-order review after
RHash. All 46 remaining recipes were inspected: 31 bootstrap recipes and 15
ordinary recipes. The earlier eight recipes retain their individual reviews.
This is a static review of build scripts, test declarations, dependencies and
patches, informed by the existing
[native-install audit](native-install-audit.md) and
[forge feature comparison](ordinary-feature-audit.md). It is not a new build of
these recipes or a fresh comparison against every upstream feedstock.

## Review rules and accepted choices

Build and installed-consumer tests should have understandable boundaries.
Compile and run an installed-library probe in its test environment, rather than
carry an uninstalled build-stage executable into package tests. Bootstrap
installed tests remain deferred until a complete stage is available. Upstream
build-tree tests are a separate concern and must honor the selected stage test
policy.

Prefer supported installation settings; where insufficient, patch upstream
installation and metadata generation before building. For now, direct patches
implementing the hidden development layout are accepted. Their directory/version
literals are a maintenance cost, not a reason to rewrite the packaging during
this annotation pass. A future channel metadata file could expose a suggested
`pkgconfigdir`, explicitly found through `PKG_CONFIG_LIBDIR`; projects could
respect that suggestion and expose their own CMake config installation variable.
The channel provider and upstream consumer work is deferred because the current
patches produce the intended layout without that coordinated change.

Shared runtime libraries and plugins stay public. Development metadata,
archives, linker interfaces and versioned headers stay hidden. In the patched pc
files, `${pcfiledir}/../..` denotes the development prefix, not the public
runtime prefix. Merely changing the shared-library install directory would mix
these two roles again. Metadata must keep resolving after environment
relocation.

Use native RUNPATH support where available. Existing post-link exceptions have
local explanations and remain unchanged pending discussion. Only imported
prebuilt payloads skip the RUNPATH audit; source-built Rust and Go applications
retain it. Rustup/toolchain preload is local to their build subprocesses; it
does not replace installed application RUNPATH. Python/rustup are imported, not
new source-build feature-parity projects. Yazi's optional external tools remain
outside the package promise; expanding Git's GUI/Tcl/Tk inventory is not
approved.

The initial annotation pass changed comments/documentation only. The maintainer
subsequently approved R1, implemented below. Other items remain a discussion
queue, not approval to implement changes.

## Items to discuss

### R1: Installed probes compiled in their test environments (implemented)

The maintainer approved moving probes for these 19 recipes: c-ares, keyutils,
libev, lzo, lz4-c, expat, libedit, icu, libpsl, libxml2, clang, libxcrypt,
libarchive, krb5, libssh2, libnghttp2, curl, jsoncpp and cppdap.

Their recipe tests now archive source files and compile/run them against the
installed package, with explicit channel compiler configuration and test-local
Clang/sysroot requirements. Clang tests use the installed compiler itself and
compile all five sanitizer/fuzzer/profile/XRay probes. Curl retains separate
shared/static probes and its existing private dependency list. Expat's
previously inline C consumer is now `tests/probe.c`. ICU no longer needs a
build-source copy of its probe or a post-link RUNPATH rewrite for that probe.

The build scripts no longer produce, run or pass these executables to tests.
Temporary `runtime-lib`, scratch bin/lib links and copying of generated probes
are removed. Test-only binaries link with an absolute RUNPATH to the installed
test environment's public lib directory; they are not installed package
payloads. Installed library/executable RUNPATH policy is unchanged. Existing
behavioral assertions and loader-environment resets remain; R5 is still pending.
Bootstrap still runs installed recipe tests only after its complete selfhost
generation. The build-only consumers in zlib, OpenSSL and PCRE2 are unchanged:
they compile and run in the same phase and are not the cross-stage problem
addressed here.

Validation: all 19 recipes render for both dirty and result variants. Using
`selfhost-channel` from the previous successful CI run `38943793434` (commit
`a385d3b602fe`), a fresh local environment compiled and ran all 24 probes and
passed the complete 19 affected script test blocks. The Clang block ran outside
the local sandbox because LeakSanitizer requires ptrace access; its assertions
were unchanged. This validates the new test commands against existing package
payloads, not a fresh build of the revised archives or their test-source
packaging. The next CI run must cover that integration. Shell syntax and recipe
source paths also passed checks.

### R2: Stage test gating

JsonCpp sets `JSONCPP_WITH_POST_BUILD_UNITTEST=ON`; consequently its build can
run unit tests even with `DEVKIT_RUN_TESTS=0`. The shell condition only controls
the later CTest invocation. R1 removed the cross-stage consumer runs from build
scripts; JsonCpp's upstream post-build test remains unchanged. Decide how to
preserve its coverage while honoring the intended stage test schedule. Compiling
a test executable without running it is not itself a test-policy violation.

### R3: Static-link metadata and dependency generation

The maintainer approved restoring upstream `@LIBS@` in `libuv-static.pc.in`,
retaining the hidden archive path. On Linux, upstream CMake generates
`-lpthread -ldl -lrt -lm`; these are system libraries supplied by the glibc
sysroot, not additional channel packages. The recipe now checks that its static
pc file is packaged, queries its linker flags, compiles/runs the installed
event-loop consumer using those flags, and rejects a dynamic libuv dependency in
that consumer.

Validation: a fresh result-variant libuv package was built locally against the
previous successful selfhost channel. All package tests passed, including the
layout/RUNPATH audit and both shared and static consumers. The static consumer
used the channel compiler configuration with its glibc 2.28 sysroot; generated
pkg-config output included all four system libraries. `DEVKIT_RUN_TESTS=0`
skipped the unrelated upstream build-tree suite for this focused verification;
installed package tests ran normally.

Still pending: libarchive's `Libs.private` and curl's private
dependencies/config-helper output are fixed lists rather than derived from
enabled backends. Libarchive retains `Requires.private`, whereas curl clears it.
These lists need consumer validation and a decision on how to keep
feature/dependency changes synchronized.

Other patched pc files often intentionally name a shared interface even with
`pkg-config --static`; that switch adds private dependencies and does not by
itself force archive selection. Distinguish that convention from a genuinely
broken static interface. Keep the already accepted direct layout patch while
discussing dependency semantics separately.

### R4: Remaining feature differences

The existing forge comparison still identifies Git's `NO_GETTEXT`, `NO_PYTHON`,
missing manuals/HTML/completion, and B4's missing TUI/completion extras. These
remain unresolved; Git GUI and Yazi external-tool expansion are separate
accepted scope choices. Lazygit's `CGO_ENABLED=0` differs from the forge
baseline and needs a DNS/NSS behavior decision; gopls matches the no-cgo
baseline.

LLVM explicitly sets LIBEDIT/TERMINFO options OFF. Before changing them, check
whether the pinned LLVM version still implements those options, which shipped
tools use them, and the exact seed baseline. Their presence alone is not proof
of missing functionality. Preserve the already documented choices around ICU
release data, libssh2's deferred SSH-service integration tests, libiconv's
library-only output and liblzma's library-only installation.

### R5: Loader environment resets

Many installed tests still unset `LD_LIBRARY_PATH`/`LD_PRELOAD`, and ICU/libxml2
do so during the build too. These are existing commands, not inherited test
configuration from `build.sh`. Consider removing redundant resets consistently
with the earlier llvm-libgcc/libcxx/libuv review. Keep unrelated variables such
as `ICU_DATA` and the intentional Rust toolchain preload as separate decisions.
The latter has a concrete upstream-binary runtime requirement.

### R6: Cleanup ownership

Gettext and libnghttp2 recursively delete every `.la` file below `PREFIX`, which
can also include installed dependency files. Contrast this with the staging
helper's ownership-based selection. Check whether to restrict cleanup to newly
installed output files; do not assume input environments contain no Libtool
archives just because today's packages often omit them.

### R7: Parallelism limits

Gopls uses `go build -p 2`; just and yazi default `CARGO_BUILD_JOBS` to two.
LLVM separately limits simultaneous link jobs to two while allowing compilation
to use `CPU_COUNT`. Review these independently: removing a compilation limit can
change peak memory, and LLVM's link pool is not a limit on all compilation. No
concurrency setting is changed by this review.

### R8: Historical CMake bootstrap patch

`bootstrap-exclude-ghs-generator.patch` guards an include under
`CMAKE_BOOTSTRAP`. The current recipe configures with previous-stage CMake, so
that guard does not affect its normal build. Decide whether to remove the
historical patch or retain it for an explicitly supported bootstrap path.

### R9: Config-helper override consistency

The libxml2 patch makes default header/library paths hidden and relocatable, but
its existing `--prefix=...` branch still assigns `libdir=$prefix/lib`. Review
subsequent `--libs` output under that override before changing behavior. PCRE2's
config helper also has prefix/exec-prefix overrides: tests currently check the
reported prefixes, but do not check all subsequent header/library outputs after
an override. This is distinct from the already accepted default layout and needs
focused consumer expectations.

## Remaining-recipe inventory

R numbers refer to the discussion queue above; a dash means no additional
specific issue was identified here, not proof of complete correctness. The
installation-interface TODO applies to the annotated layout patches in addition
to the entries below.

| Recipe              | Review focus / discussion                                                            |
| ------------------- | ------------------------------------------------------------------------------------ |
| c-ares              | Threaded shared/static interfaces, no GoogleTest suite as in seed; R1, R5            |
| keyutils            | Userspace ABI probe, kernel/root integration scope, symbol-map fix; R1, R5           |
| libev               | Compatibility headers, Libtool link policy; R1, R5                                   |
| bzip2               | Separate shared Make build, native RUNPATH, compression round trip; R5               |
| zlib                | Native CMake exports, test fixtures, build-only consumer; —                          |
| zstd                | Native shared/static build and separate Make pzstd runtime flags; R5                 |
| lzo                 | Native static/shared installation and both include spellings; R1, R5                 |
| lz4-c               | Preserve target-specific pthread flags and forge compression corpus; R1, R5          |
| expat               | Generated Autotools CMake metadata, runtime/meta output split; R1, R5                |
| ncurses             | Narrow/wide headers, tinfo, generated-script maintenance, LLD workaround; R5         |
| libedit             | Narrow ncurses headers and Libtool build-tree linking; R1, R5                        |
| libiconv            | Library-only install and extra encodings retained; R5                                |
| liblzma             | Library-only install, upstream tool tests, native codec defaults; R5                 |
| icu                 | Release production data, separate consumer metadata and loader wrappers; R1, R5      |
| libpsl              | Release DAFSA inputs, ICU backend, excluded Python regeneration helper; R1, R5       |
| gettext             | Seed feature baseline, generated source inputs, private runtime SONAMEs; R5, R6      |
| libxml2             | Zlib exact linker input, source-generated exports and config helper; R1, R5, R9      |
| clang               | Compiler/runtime ownership, explicit channel config, probe packaging; R1, R4, R5, R7 |
| libxcrypt           | Perl source generator, disabled obsolete-ABI map correction; R1, R5                  |
| perl                | Separate generated consumer Config files and explicit install selection; —           |
| ca-certificates     | Pinned original data, no compiler or development staging; —                          |
| openssl             | Native generators, public provider modules, build-only consumer; R5                  |
| libarchive          | Channel compression/XML/crypto backends and generated metadata; R1, R3, R5           |
| krb5                | Official generated release, NLS, case-sensitive metadata install variable; R1, R5    |
| libssh2             | OpenSSL/zlib features, deferred external-SSH integration suite; R1, R5               |
| libnghttp2          | Native applications, C++20 compiler flags, shipped man pages; R1, R5, R6             |
| curl                | Enabled backend inventory, static metadata and relocated config helper; R1, R3, R5   |
| jsoncpp             | Native shared/static/object exports and post-build tests; R1, R2, R5                 |
| cppdap              | Private test-only GTest, external JsonCpp, shared SONAME/static archive; R1, R5      |
| ninja               | Release lexer, pinned offline GTest, native installation RUNPATH; R5                 |
| cmake               | Channel system libraries, ccmake/debugger, host-default discovery; R5, R8            |
| b4                  | Offline locked wheel environment, native-wheel RUNPATH exemption; R4                 |
| difftastic          | Source Cargo build, scoped toolchain preload, native RUNPATH; R5                     |
| fd                  | Source Cargo build, generated completion commands, native RUNPATH; R5                |
| git                 | Native per-location RUNPATH, rustup-scoped build, PCRE2/HTTP inputs; R4, R5          |
| go                  | Imported official layout and GOROOT relocation, RUNPATH exemption; —                 |
| gopls               | Source no-cgo build and isolated workspace test; R7                                  |
| just                | Source Cargo build, generated man/completions, native RUNPATH; R5, R7                |
| lazygit             | Source vendored Go build and Git runtime dependency; R4                              |
| pcre2               | All widths/JIT/Unicode, shared/static CMake consumer tests; R9                       |
| python              | Imported uv-managed layout and native extensions/venv tests; —                       |
| ripgrep             | Dynamic channel PCRE2, native RUNPATH and behavioral -P test; R5                     |
| rust-toolchain-lock | Metadata-only exact toolchain version; —                                             |
| rustup              | Imported manager, local runtime adaptation, RUNPATH exemption; R5                    |
| uv                  | Source build, package-manager feature choices, generated completions; R5             |
| yazi                | Default Cargo features, optional external helpers outside promise; R5, R7            |
