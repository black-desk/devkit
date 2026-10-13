# Per-package development-prefix review

The first PR revision had only a focused zlib package build and general layout
checks. That was insufficient: dirty CI failed because llvm-libgcc called a
helper absent from its source inputs. Review found the same omission in libcxx,
and both recipes now explicitly include the compiler packaging sources.

## What was checked

All changed build scripts were reviewed for source snapshots, dependency header
and linker paths, metadata production, staging order and installed RUNPATH. The
current published archives for the 37 native packages below were downloaded and
staged individually using the migration helper. Staging and hidden-library
symlink resolution passed for every payload. Those checks reuse existing built
files; they are not new builds of all 37 recipes.

The staged files were assembled into a temporary prefix. All 51 pkg-config
interfaces produced existing header/library paths. CMake configuration loading
and referenced-file checks passed for zstd, libxml2, jsoncpp, libuv, Expat,
cppdap, libssh2, PCRE2, OpenSSL, c-ares, LLVM and Clang. A regression check also
loads configured library directories, object files and executable exports after
moving the prefix. Source rebuilding verified zstd's versioned include export.

Small programs were compiled and run through each of the 31 library interfaces.
The table identifies the extra coverage; every row also had its payload staged.
Tests ran without LD_LIBRARY_PATH or LD_PRELOAD. The old libxml2 payload failed
independent linkage, so its corrected source build was tested separately rather
than adding zlib to the consumer's own link command.

| Recipe      | Additional focused coverage                                               |
| ----------- | ------------------------------------------------------------------------- |
| bzip2       | Shared library version API                                                |
| c-ares      | Existing library probe and CMake export                                   |
| clang       | LLVM/Clang exports, object files, tool locations; packaging-source review |
| cmake       | System-library paths, native install RUNPATH and discovery-test review    |
| cppdap      | Existing C++ probe, external jsoncpp export                               |
| curl        | Existing runtime probe; shared/private dependency flags                   |
| expat       | Parser consumer and CMake export                                          |
| gettext     | libgettextpo consumer; private runtime SONAME exceptions                  |
| icu         | Versioned headers, converter/collation/date/data probe, Make metadata     |
| jsoncpp     | Existing C++ probe; exported object-library files                         |
| keyutils    | Existing probe; missing pkg-config prefix                                 |
| krb5        | Existing probe; config helper linker/RUNPATH separation                   |
| libarchive  | Existing probe; explicit versioned dependency paths                       |
| libcxx      | C++20 exceptions, threads, filesystem and unwinder identity               |
| libedit     | Existing tokenizer probe                                                  |
| libev       | Existing event-loop probe                                                 |
| libiconv    | Character-conversion consumer                                             |
| liblzma     | Library version consumer                                                  |
| libnghttp2  | Existing HTTP/2 library probe                                             |
| libpsl      | Existing public-suffix probe                                              |
| libssh2     | Existing probe and CMake export                                           |
| libuv       | Existing version/runtime probe and CMake export                           |
| libxcrypt   | Existing password-hashing probe                                           |
| libxml2     | Corrected source build, zlib DT_NEEDED, independent parser consumer       |
| llvm-libgcc | Actual seed-mode package build and runtime tests; fresh-cache meta test   |
| lz4-c       | Existing compression probe                                                |
| lzo         | Existing compression probe through both supported include roots           |
| make        | Bootstrap/relink flags and install depth review                           |
| ncurses     | Header nesting, tinfo linkage and config-helper flags                     |
| ninja       | Native build/install runtime-path review                                  |
| openssl     | TLS context consumer; runtime plugin retention and CMake export           |
| pcre2       | Unicode/JIT/matching probes for 8, 16 and 32 bits; executable exports     |
| perl        | XS metadata, hidden libcrypt discovery and module install depths review   |
| pkgconf     | Host-default metadata paths and native linker-argument review             |
| rhash       | SHA256 library interface                                                  |
| zlib        | Actual seed-mode package build, 18 upstream tests and relocated consumers |
| zstd        | Source-built exports and independent Make-built pzstd RUNPATH/round trip  |

The ordinary source-built tools (fd, ripgrep, just, uv, difftastic, yazi and
Git) were reviewed for hidden dependency discovery and native runtime paths.
Cargo tooling retains its scoped unwinder preload; installed tools and
completion generators use their public runtime directories. Go tools, imported
Python, rustup, data packages and metadata-only outputs received required
revision bumps; their unchanged installation methods were not rebuilt locally.

## Problems fixed by this review

- Missing helper sources in llvm-libgcc and libcxx.
- Missing native RUNPATH in zstd's separate pzstd Make build.
- Unmoved jsoncpp object files, which also broke cppdap configuration.
- Exported executable paths pointing into a nonexistent hidden bin directory.
- Libxml2 configuration searching public lib for its removed linker interface.
- Missing keyutils prefix and ICU's spaced pkg-config assignments.
- ICU Make header/linker paths and config-helper runtime paths.
- LZO metadata lacking the parent directory required by `lzo/lzo1x.h`.
- Potential duplicated ncurses version directories in generated config helpers.
- Libtool discarding libxml2's absolute zlib shared-library input.

The llvm-libgcc main package built and passed its tests. Its temporary meta uses
the seed's exact package identity; the builder initially collected old GNU
libgcc tests from an existing cache. Testing the built meta with a separate
RATTLER_CACHE_DIR passed. Dirty-stage package tests are already deferred by the
bootstrap design, and this does not change stage channel selection.

## What remains for CI

These checks do not establish that every new recipe builds successfully or that
all upstream test suites pass. Full dirty, result, selfhost, independent smoke
and ordinary-package jobs remain required. CMake's new binary, the complete LLVM
compiler and most other producers have not been rebuilt locally. The annotated
post-install ELF exceptions remain as documented in the layout policy.
