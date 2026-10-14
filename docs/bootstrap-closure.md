# Bootstrap closure inventory

This inventory covers every archive in `seed-packages.tsv`, using the exact
archive's `depends` metadata in the local seed repodata. It is a source/package
inventory, not proof of a successful bootstrap. Host virtual packages such as
`__glibc` are outside the channel by policy. The manifest now also includes the
approved gettext-tools 0.25.1 input.

All **45 seed packages** are reachable from the declared seed tool/sysroot
inputs; their non-virtual dependency names are all present in the manifest.

| Seed member/version               | Representative dependency path                      | Channel carrier           | Status                                                                                                  |
| --------------------------------- | --------------------------------------------------- | ------------------------- | ------------------------------------------------------------------------------------------------------- |
| `_openmp_mutex` 4.5               | `clang-23 → libgcc → _openmp_mutex`                 | LLVM toolchain transition | seed GNU support; replaced/removed in final LLVM toolchain (see below)                                  |
| `bzip2` 1.0.8                     | `cmake → bzip2`                                     | bzip2                     | recipe scheduled; entire generation unverified                                                          |
| `c-ares` 1.34.8                   | `cmake → libcurl → libnghttp2 → c-ares`             | c-ares                    | Clang build and independent package tests passed; whole generation unverified                           |
| `ca-certificates` 2026.7.22       | `cmake → libcurl → openssl → ca-certificates`       | ca-certificates           | recipe scheduled; entire generation unverified                                                          |
| `clang-23` 23.1.3                 | `clang-23`                                          | clang                     | recipe scheduled; entire generation unverified                                                          |
| `cmake` 3.31.8                    | `cmake`                                             | cmake                     | recipe scheduled; entire generation unverified                                                          |
| `compiler-rt23` 23.1.3            | `clang-23 → compiler-rt23`                          | llvm-libgcc / clang       | partial coverage; full runtime feature restoration pending                                              |
| `compiler-rt23_linux-64` 23.1.3   | `clang-23 → compiler-rt23 → compiler-rt23_linux-64` | llvm-libgcc / clang       | partial coverage; full runtime feature restoration pending                                              |
| `gettext-tools` 0.25.1            | `gettext-tools`                                     | gettext                   | Clang build, full upstream suite and both independent package tests passed; whole generation unverified |
| `gnuconfig` 2025.07.09            | `gnuconfig`                                         | gnuconfig                 | recipe scheduled; entire generation unverified                                                          |
| `icu` 78.3                        | `clang-23 → libxml2 → icu`                          | icu                       | recipe scheduled; entire generation unverified                                                          |
| `kernel-headers_linux-64` 4.18.0  | `sysroot_linux-64 → kernel-headers_linux-64`        | sysroot                   | recipe scheduled; entire generation unverified                                                          |
| `keyutils` 1.6.3                  | `cmake → libcurl → krb5 → keyutils`                 | keyutils                  | Clang/LLD build and independent package tests passed; whole generation unverified                       |
| `krb5` 1.22.2                     | `cmake → libcurl → krb5`                            | krb5                      | Clang build with translations and independent tests passed; whole generation unverified                 |
| `libclang-cpp23.1` 23.1.3         | `clang-23 → libclang-cpp23.1`                       | clang                     | recipe scheduled; entire generation unverified                                                          |
| `libcurl` 8.22.0                  | `cmake → libcurl`                                   | curl                      | Clang build and carrier/meta tests passed; own-only runtime closure verified                            |
| `libedit` 3.1.20260512            | `cmake → libcurl → krb5 → libedit`                  | libedit                   | Clang build and independent package tests passed; whole generation unverified                           |
| `libev` 4.33                      | `cmake → libcurl → libnghttp2 → libev`              | libev                     | Clang build and independent package tests passed; whole generation unverified                           |
| `libexpat` 2.8.5                  | `cmake → libexpat`                                  | expat                     | Clang build, upstream and carrier/meta tests passed; whole generation unverified                        |
| `libgcc` 16.2.0                   | `clang-23 → libgcc`                                 | LLVM toolchain transition | seed GNU support; replaced/removed in final LLVM toolchain (see below)                                  |
| `libgcc-devel_linux-64` 16.2.0    | `libgcc-devel_linux-64`                             | LLVM toolchain transition | seed GNU support; replaced/removed in final LLVM toolchain (see below)                                  |
| `libgomp` 16.2.0                  | `clang-23 → libgcc → _openmp_mutex → libgomp`       | LLVM toolchain transition | seed GNU support; replaced/removed in final LLVM toolchain (see below)                                  |
| `libiconv` 1.18                   | `clang-23 → libxml2 → libiconv`                     | libiconv                  | recipe scheduled; entire generation unverified                                                          |
| `libllvm23` 23.1.3                | `clang-23 → libllvm23`                              | clang                     | recipe scheduled; entire generation unverified                                                          |
| `liblzma` 5.8.3                   | `cmake → liblzma`                                   | liblzma                   | recipe scheduled; entire generation unverified                                                          |
| `libnghttp2` 1.68.1               | `cmake → libcurl → libnghttp2`                      | libnghttp2                | Clang/libc++ build, upstream suites and independent tests passed; whole generation unverified           |
| `libpsl` 0.23.1                   | `cmake → libcurl → libpsl`                          | libpsl                    | Clang build, upstream suites and independent package tests passed; whole generation unverified          |
| `libssh2` 1.11.1                  | `cmake → libcurl → libssh2`                         | libssh2                   | Clang build, standalone CTest and independent package tests passed; SSH integration deferred            |
| `libstdcxx` 16.2.0                | `clang-23 → libstdcxx`                              | LLVM toolchain transition | seed GNU support; replaced/removed in final LLVM toolchain (see below)                                  |
| `libstdcxx-devel_linux-64` 16.2.0 | `libstdcxx-devel_linux-64`                          | LLVM toolchain transition | seed GNU support; replaced/removed in final LLVM toolchain (see below)                                  |
| `libuv` 1.52.1                    | `cmake → libuv`                                     | libuv                     | recipe added; full source suite and independent package tests passed; whole generation unverified       |
| `libxml2` 2.15.4                  | `clang-23 → libxml2`                                | libxml2                   | recipe scheduled; entire generation unverified                                                          |
| `libxml2-16` 2.15.4               | `clang-23 → libxml2-16`                             | libxml2                   | file-free compatibility meta built; mixed-environment ownership verified; entire generation unverified  |
| `libzlib` 1.3.2                   | `clang-23 → libzlib`                                | zlib                      | recipe scheduled; entire generation unverified                                                          |
| `lld` 23.1.2                      | `lld`                                               | clang                     | recipe scheduled; entire generation unverified                                                          |
| `llvm-tools` 23.1.3               | `llvm-tools`                                        | clang                     | recipe scheduled; entire generation unverified                                                          |
| `llvm-tools-23` 23.1.3            | `llvm-tools → llvm-tools-23`                        | clang                     | recipe scheduled; entire generation unverified                                                          |
| `make` 4.4.1                      | `make`                                              | make                      | recipe scheduled; entire generation unverified                                                          |
| `ncurses` 6.6                     | `cmake → ncurses`                                   | ncurses                   | recipe scheduled; entire generation unverified                                                          |
| `ninja` 1.13.2                    | `ninja`                                             | ninja                     | recipe scheduled; entire generation unverified                                                          |
| `openssl` 3.6.5                   | `cmake → libcurl → openssl`                         | openssl                   | recipe scheduled; entire generation unverified                                                          |
| `rhash` 1.4.6                     | `cmake → rhash`                                     | rhash                     | source and independent package tests passed; whole generation unverified                                |
| `sysroot_linux-64` 2.28           | `sysroot_linux-64`                                  | sysroot                   | recipe scheduled; entire generation unverified                                                          |
| `tzdata` 2026c                    | `sysroot_linux-64 → tzdata`                         | seed import               | explicit imported data exception                                                                        |
| `zstd` 1.5.7                      | `clang-23 → zstd`                                   | zstd                      | recipe scheduled; entire generation unverified                                                          |

All seed members now have a carrier recipe or an explicit transition/import
policy. Libnghttp2 validation is complete individually; this does not complete
the closure. Kerberos has passed its initial seed-msgfmt build and independent
package tests. Libssh2 is validated individually and scheduled after OpenSSL.
Its Docker/SSHD integration tests are explicitly deferred until OpenSSH is
packaged, as agreed. Neither Docker nor OpenSSH is added to the bootstrap seed,
and host SSHD is not used. Library features remain enabled; standalone CTest
checks and the independent library probe remain enabled. Tests needing static
libssh2 are unavailable under the seed's shared-only configuration. The approved
gettext/msgfmt provider has been added to seed and bootstrap; its Clang build
and independent package validation are complete. Keyutils is patched, validated
individually and scheduled in bootstrap order. All closure carrier recipes are
now scheduled; complete generation validation is pending.

Perl, pkgconf, libcxx and llvm-libgcc are additional channel build/runtime
members even where their package names do not occur in seed. Newly added recipes
can have further build dependencies; those must be included too.

## Functional coverage

- LLVM: zlib/zstd/libxml2 and all stable targets have been restored in the Clang
  configuration; that expanded build remains unverified. The earlier minimal
  carrier passing tests does not validate these settings. Compiler-rt sanitizer,
  XRay, fuzzer, profile and ORC coverage remains pending.
- CMake: the existing recipe uses bundled third-party libraries and has not
  restored the forge system-library configuration or ccmake. Preserve the actual
  seed CMake 3.31.8 baseline, rather than assuming current feedstock HEAD is
  identical. Its curl dependency introduces the network/authentication library
  chain recorded above.
- Curl: HTTP/2, SSH, GSSAPI, PSL, zstd, WebSocket protocols and built-in manual
  have been restored to the native seed baseline. A file-free libcurl interface
  is added; carrier/meta tests and an own-only runtime installation passed.
  HTTP/3, IDN2, Brotli and LDAP are also absent from the exact seed archive
  baseline.
- bzip2: the new recipe keeps static/shared libraries and command-line tools,
  with version-isolated headers. Its upstream shared Makefile needs a patch to
  honor compiler/linker flags. Source/package verification is tracked below.
- Expat: dirty compiler support, bootstrap membership and file-free libexpat
  output are complete. The seed example/test coverage, xmlwf and shipped manual
  are retained; Clang, upstream suite and both archive tests pass.
- Library tests completed individually do not validate a whole generation.

## GNU seed support and file ownership

GNU libgcc/libstdcxx and development support belong to the seed toolchain. The
final channel intentionally uses LLVM-libgcc/libcxx instead; libcxx is not an
ABI-compatible replacement for libstdcxx inside an unmodified seed binary. The
seed's libgcc metadata also pulls in the OpenMP mutex and GNU libgomp; this
metadata chain disappears when the GNU runtime is removed. LLVM OpenMP support,
if required by the compiler feature baseline, needs separate verification.

The dirty-only libgcc meta and libxml2-16 meta replace the overlapping seed
packages. A fresh mixed-tool installation confirms LLVM-libgcc alone owns
`lib/libgcc_s.so.1`, libxml2 alone owns `lib/libxml2.so.16`, and both aliases
own no files. This resolves the observed file collisions; it does not prove
complete GNU runtime ABI compatibility or a complete bootstrap generation.

## Next work

1. Keep the verified file-free compatibility interfaces while completing the
   remaining bootstrap dependencies.
2. Restore and validate full CMake against the completed dependency recipes.
3. Validate the expanded LLVM compiler/runtime feature set.
4. Build a clean complete dirty generation and run deferred package/channel
   tests. Only then run result and the immutable-input result self-host rebuild.

## Latest leaf-package validation

Bzip2 1.0.8 build 0 completed with seed Clang and LLVM binary tools, using an
isolated temporary input channel containing Make plus seed. Upstream compression
fixtures and a shared-library roundtrip passed. Independent package checks also
passed (tools, static/shared libraries, isolated header, RUNPATH, roundtrip).
This adds one validated leaf, not a completed dirty generation. The seed archive
manifest is unchanged; bzip2 was already a member. Bootstrap order, variant
rendering and the channel-wide expected package set now include this recipe.

The dirty-only libgcc meta experiment now resolves the GNU/LLVM file ownership
conflict in a focused seed-tool environment; result rendering omits the meta.
LLVM-libgcc build 5 applies the approved dirty-only `--allow-shlib-undefined`
workaround, with a TODO explaining the six missing GCC_4.3.0 versions. New
GNU-libstdc++ executable/DSO probes pass with immediate binding and no loader
overrides, including in the mixed environment containing rebuilt libxml2. See
clang-bootstrap.md for the scope and limitations.

Libuv's full shared-library source suite passes when run using
`systemd-run --user --slice cgtproxy-direct.slice -P COMMAND`. The local
transparent proxy made invalid DNS names resolve and unreachable TCP targets
connect, causing four failures in the ordinary environment. The direct slice is
a local cgtproxy configuration, not a CI dependency or recipe test exemption.

RHash 1.4.6 uses the exact seed archive's conda-forge recipe as the feature
baseline: OpenSSL acceleration is disabled there as well, rather than removed
for this transition. The channel recipe builds shared/static libraries and the
CLI, runs upstream library/CLI suites, isolates headers, and installs
relocatable pkg-config metadata. RHash is now included in stage ordering and
channel checks. Libxml2 build 1 and the file-free libxml2-16 meta passed
independent package tests.

RHash build 0 passed upstream static/shared library and full CLI suites, plus
independent archive tests (contents, SHA-256 output, RUNPATH, header isolation).

## Additional leaf validation and keyutils version-script correction

C-ares 1.34.8, libev 4.33 and libedit 3.1.20260512 build 0 passed Clang builds
and independent package tests. C-ares preserves seed thread/tool support, adds
static content, and checks numeric address callbacks without external DNS. The
seed does not enable GoogleTest-dependent upstream tests. Libev retains all
three isolated headers, including event.h, static/shared libraries, and tests a
timer and the compatibility interface. Upstream make check has no test programs.
Libedit matches seed shared-only output, uses channel ncurses, and verifies
history and quoted tokenization. All carriers have relative RUNPATH.

Keyutils 1.6.3 uses the exact seed source and two conda-forge patches. Its
version.lds lists nonexistent keyctl_restrict and keyctl_dh_compute_kdf_alloc
under KEYUTILS_1.7; LLD refuses these assignments. The source instead exports
keyctl_restrict_keyring, unversioned in the seed GNU-linked library. That seed
also lacks the nonexistent symbols. The approved patch removes only the two
nonexistent assignments, preserving the seed function ABI without a linker
relaxation. It deliberately does not rename the first entry to
keyctl_restrict_keyring, which would change that function’s symbol version.
Kernel/root-dependent keyutils integration tests are also omitted by the seed;
the recipe adds a userspace version/error-propagation probe without keyring
writes.

Upstream Git history confirms both inconsistencies were introduced in 2017:

- [a28ec8156908](https://git.kernel.org/pub/scm/linux/kernel/git/dhowells/keyutils.git/commit/?id=a28ec81569084ad9254239af1f16aee35ef0d52b)
  added keyctl_restrict_keyring to both the implementation and header, but added
  the different name keyctl_restrict to version.lds in the same commit.
- [badd34263aff](https://git.kernel.org/pub/scm/linux/kernel/git/dhowells/keyutils.git/commit/?id=badd34263aff2c53749774589310d232c31b8f4b)
  implemented/declared keyctl_dh_compute_kdf, while listing both that function
  and keyctl_dh_compute_kdf_alloc in version.lds. No alloc implementation or
  declaration was added. The fetched history has no later addition/removal of
  that alloc name, and fetched remote branches contain it only in version.lds.

Fetched upstream master c076dff259e9 retains both entries; its version.lds is
identical to v1.6.3. This is not a conditional compilation omission introduced
by the channel. The alloc entry's author's intent cannot be established from the
commit alone. The recipe now applies remove-nonexistent-version-symbols.patch,
whose TODO requests upstreaming and records the introducing commits.

Keyutils build 0 passed Clang/LLD compilation, its userspace probe and
independent package tests. All 41 public function names and symbol versions
match the seed library, including unversioned keyctl_restrict_keyring; all
KEYUTILS version nodes remain defined. The recipe is included in bootstrap
ordering, variant rendering and the final channel expected-package checks.

## Libpsl validation and Kerberos build prerequisite

Libpsl 0.23.1 build 0 uses upstream Autotools instead of the seed's Meson path,
with the same ICU runtime and built-in public suffix data. The official tarball
contains src/suffixes_dafsa.h and both test DAFSA files; configure explicitly
requires Python only when these files are absent. No generated-data patch is
needed. Three library and five CLI upstream tests plus independent archive
checks passed, including cookie-domain boundaries and ICU Unicode lowercase. The
Python regeneration helper is excluded, as it is from the seed carrier; the
native psl command and man page are retained. Header isolation, relative RUNPATH
and relocatable pkg-config metadata follow channel policy.

MIT's official krb5 1.22.2 distribution includes configure and ordinary build
scripts, unlike the seed recipe's GitHub snapshot requiring autoreconf. It still
contains only .po translation sources, not .mo catalogs. src/po/Makefile.in uses
msgfmt to compile these; configure silently omits the po build when msgfmt is
absent. The exact seed recipe includes gettext/gettext-tools, so silently
omitting translations would reduce its functionality. The approved solution adds
gettext-tools 0.25.1 to seed and a full gettext carrier plus file-free
gettext-tools alias to the channel. No --disable-nls workaround has been
introduced.

OpenSSL 3.5.9 build 1 was also rebuilt in dirty mode with seed Clang/LLVM tools
and channel Perl 5.44.0. The upstream suite passed (347 test files, 4,518
tests), followed by independent package tests of the CLI, providers, consumer
binary, isolated headers, pkg-config metadata and relocatable RUNPATH. This
validates the current OpenSSL recipe, not the remaining complete bootstrap
generation.

The new seed input is gettext-tools-0.25.1-h0e23cf9_2.conda, pinned by archive
SHA-256 and size. Its runtime dependencies are already seed members; no other
archive was added. The offline seed solve passes with exactly 45 packages.
Gettext 0.25.1 build 0 preserves conda-forge's native feature configuration,
uses channel libc++/LLVM-libgcc and libiconv, and passed the full upstream
suite: 988 passes, 137 upstream optional skips, zero failures/errors (1,125
entries). Both the carrier and file-free gettext-tools meta passed independent
archive tests. A fresh alias-only installation selects only own libraries, has
no GNU runtime packages, and assigns bin/msgfmt solely to gettext.

The Libtool-only -no-install flag is restricted to build/install, so autopoint's
plain C fixtures do not inherit it during make check. Local lang-go downloads
need proxy connectivity: direct proxy.golang.org access timed out, and rattler
clears caller Go-cache environment variables. The successful complete run used
cgtproxy-proxy.slice outside the Codex sandbox. This is local execution setup,
not a recipe feature reduction, CI dependency, or test exemption.

Kerberos 1.22.2 build 0 passed Clang builds first with seed msgfmt and then with
the self-built gettext-tools alias selected in BUILD_PREFIX. Independent tests
passed for both builds: German/Georgian catalogs, principal roundtrip, commands,
headers and RUNPATH. Self-built msgfmt generated a German .mo byte-identical to
the seed-msgfmt output. Kerberos retains OpenSSL, keyutils, libedit, bundled
verto and explicit --enable-nls; it is scheduled after OpenSSL. The seed does
not run the Python/KDC integration suite; the current recipe uses an independent
public API probe. No complete dirty/result/self-host generation is claimed.

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
focused tests. The clean dirty generation now passes all deferred tests and the
44-package stage-only closure/policy checks. Result and self-host validation
remain in progress.

A fresh own-channel-only libarchive installation selects 14 packages, including
LZO/LZ4, without GNU libgcc/libstdcxx/libgomp. With loader overrides unset,
bsdtar and libarchive.so resolve host glibc and channel libraries for all other
dependencies. LZ4's packaged library/CLI license texts were also checked.

### External JSON and Debug Adapter Protocol libraries

Jsoncpp 1.9.8 provides shared/static libraries, versioned isolated headers and
its upstream CMake targets. Cppdap 1.65.0 is pinned to upstream commit
`c69444ed76f7468b232ac4f989cb8f2bdc100185`, the exact revision bundled by CMake
3.31.8. It uses channel jsoncpp, with shared/static libraries and isolated
headers. Its shared SONAME is restricted to protocol minor version 1.65; a small
patch adds versioning and another fixes the installed CMake config's missing
JsonCpp dependency. Both patches carry upstream TODOs.

GoogleTest 1.12.1 is downloaded as test-only cppdap source, built with the same
Clang/libc++ toolchain and installed into a temporary build-tree prefix. It is
not a seed package, closure carrier or channel runtime dependency. Upstream unit
tests are enabled explicitly; no missing-submodule fallback is accepted.
CMake/ccmake build against these external libraries and pass the forge-baseline
upstream tests. Packaged consumer/runtime checks have also passed.

The source-built sysroot always installs its canonical `x86_64-pc-linux-gnu`
layout, matching the channel compiler configuration. Dirty builds additionally
provide a relative `x86_64-conda-linux-gnu` compatibility symlink for seed
compilers. Deferred consumer tests use the canonical path in every stage;
otherwise a dirty-stage compiler would refer to a sysroot absent from its
completed channel. The alias contains no additional glibc copy. Inside the
sysroot, preserve the Rocky RPM paths under `/usr`, including `/usr/lib64`
for runtime libraries, linker scripts, static libraries and startup objects.
For root directories absent from these RPMs, recreate Rocky's relative
`bin`, `sbin`, `lib` and `lib64` links into `/usr`, normally supplied by its
filesystem RPM. Preserve directories actually present in the inputs, including
`/sbin` containing `ldconfig`. In particular, `/lib64 -> usr/lib64`
resolves the original glibc linker-script paths. Do not merge the RPM contents
into a different directory to imitate conda-forge's sysroot layout. This does
not change the channel's own `<prefix>/lib` layout. Upstream conda-forge
reverses the `/lib64` symlink and merges library directories to work around
[conda-build prefix detection](https://github.com/conda/conda-build/issues/5853);
we use rattler-build and have verified native-layout Clang/LLD C and libc++
consumer links locally. Full bootstrap validation of this layout remains pending.

Retain conda-forge's removal of legacy glibc `libnsl` and `rpcsvc/yp*` headers:
[the upstream compatibility report](https://github.com/conda-forge/rasterio-feedstock/issues/220)
shows that automatic detection can introduce a `libnsl.so.1` runtime dependency
absent on modern hosts. NIS consumers should use a separately packaged channel
`libnsl`, rather than assuming the host provides the legacy library.

The external-library CMake package tests pass, including compiling/running a
channel-libc++ consumer and checking ccmake's ncurses linkage. A fresh
channel-only runtime installation has no GNU runtime packages; an ldd audit of
cmake/ctest/cpack/ccmake and jsoncpp/cppdap finds host glibc and channel
libraries exclusively. The result-variant graph audit renders all 58 package
nodes with 392 dependency edges and no non-bootstrap dependency cycles.
