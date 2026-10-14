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
metadata is left untouched. The generic metadata fallback remains for
imported/legacy inputs; current source recipes generate their paths before
installation.

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
| `perl`                | Patch installperl to normalize installed XS Config modules only; build-time modules remain unchanged.                                                                 |
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
- Perl: exercised installed-Config normalization against fixtures, including
  variable-length Config.pm entries; also loaded normalized real Config modules
  with Perl 5.44. Original build inputs are untouched.
- Repository packaging/pipeline tests, shell syntax, recipe rendering and patch
  application checks accompany the change.

These targeted checks do not replace the dirty/result/selfhost CI rebuild and
stage-level installed behavior tests. LLVM/Clang has not been rebuilt locally
for this installation change.

Post-link ELF exceptions are separate from development installation: existing
annotated finalize-elf uses remain until each build system supports the required
per-file installed RUNPATH. See [development-layout.md](development-layout.md).
