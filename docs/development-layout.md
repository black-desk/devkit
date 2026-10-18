# Installation layout and host-default discovery

The Conda environment root remains the installation prefix. Executables are
installed in `bin`; other configurable directories live under `lib/devkit`:

```text
<prefix>/bin/
<prefix>/lib/devkit/lib/                         # runtime DSOs and linker files
<prefix>/lib/devkit/lib/pkgconfig/
<prefix>/lib/devkit/lib/cmake/<package>/
<prefix>/lib/devkit/include/<package>-<version>/
<prefix>/lib/devkit/share/
<prefix>/lib/devkit/libexec/<package>/bin/        # development query helpers
<prefix>/lib/devkit/etc/
<prefix>/lib/devkit/var/
```

Configure upstream install directories directly, keeping `CMAKE_INSTALL_PREFIX`
(or `--prefix`) at the environment root and bindir public. Shared and static
libraries use the same private libdir. Let upstream generate its pkg-config and
CMake configuration from those directories, preserving generated dependencies.
Do not move these metadata files merely to give them a private location.

Keep remaining exceptions local to their recipe. OpenSSL lacks an independent
includedir option; bzip2 lacks independent install directories; Expat's
Autotools exports contain hardcoded header paths. These recipes retain narrowly
scoped installation adjustments. Complex adjustments belong in recipe-owned
Python files; simple file moves/substitutions remain in shell. Do not introduce
a shared staging abstraction before channel coverage is complete.

Versioned header directories retain each project's native internal hierarchy.
For example, libxml2 installs `libxml2-2.15.4/libxml2/libxml/*.h`; its generated
metadata supplies the nested include path. Recipes with hand-written include
flags must follow it.

## Default tools use the host

Adding public `bin` to PATH must not opt ordinary projects into channel
libraries. CMake derives public search prefixes from PATH, and those prefixes
contain no public development interfaces. pkgconf retains an explicit list of
host pkg-config directories instead of its own prefix-based defaults.

CMake's own modules remain in `share/cmake-3.31`. Its Unix platform module
derives a system search prefix from `CMAKE_ROOT`; putting those resources under
the private prefix would make other channel packages discoverable by default.
CMake's documentation and other configurable resources remain private. No patch
to CMake's package-search implementation is required.

Development query helpers (`curl-config`, `krb5-config`, `xml2-config`, ncurses,
PCRE2 and LLVM helpers) live in private libexec directories, off PATH. Recipes
use their explicit paths when needed. LLVM's helper retains a small patch for
its separate install directory, prefix inference and native install RUNPATH.

Channel builds opt in with `CMAKE_PREFIX_PATH=<prefix>/lib/devkit`,
`PKG_CONFIG_LIBDIR=<prefix>/lib/devkit/lib/pkgconfig`, and the explicit compiler
configuration in `lib/devkit/share/devkit/clang.cfg`. Native pkg-config metadata
retains the environment root as `prefix`; consumers must not request pkgconf's
`--define-prefix`, which would incorrectly reinterpret the private metadata
location as the environment root. Conda performs recorded text-prefix
substitution at installation, including the upstream-generated metadata.

## Runtime paths

Use build-system support for distinct build/install paths where available.
Installed ELF uses DT_RUNPATH with paths relative to `$ORIGIN`; automatic
rattler-build binary relocation remains disabled so it cannot convert RUNPATH to
DT_RPATH. A public executable typically uses `$ORIGIN/../lib/devkit/lib`; a
library in the private libdir uses `$ORIGIN`. Private helpers and plugins need
paths appropriate to their actual depth. Symlinked executables require the
executable's real installation location; shared objects loaded through aliases
can use the alias directory as ORIGIN.

Document existing post-link exceptions in their recipes. The shared
`scripts/packaging/finalize-elf.py` computes paths to the private libdir only
for newly installed ELF files; installed dependency ownership records protect
build inputs. Installing a Conda package may substitute recorded prefixes, but
does not replace our RUNPATH policy with automatic patchelf relinking.

## Bootstrap compatibility

Seed GNU libgcc remains in public `lib`, while channel LLVM-libgcc installs in
private `lib/devkit/lib`. These packages no longer collide, so the dirty libgcc
metadata-only replacement and seed-version variant generator are removed. Seed
tools can use GNU's runtime; rebuilt tools select the private runtime. Identical
SONAMEs still allow a process to reuse an already loaded runtime, so this is
directory separation, not guaranteed per-process runtime isolation.

Dirty library packages additionally provide public SONAME aliases needed by seed
tools' existing public RPATH entries. Do not expose unversioned linker `.so`
names or private metadata there. Include libc++/ABI aliases because seed tools
may load dirty C++ dependencies through a public runtime alias. Never alias
LLVM's `libgcc_s.so.1` over seed GNU libgcc. Result/selfhost omit these
compatibility aliases and contain no GNU libgcc/libstdcxx package.

The seed manifest itself is unchanged. Imported sysroot/tzdata and imported
language toolchain internal trees keep their purposeful upstream layouts. These
exceptions do not expose ordinary channel C/C++ development interfaces.

## Validation

`scripts/packaging/check-package.py` checks package-owned installed files and
ELF properties. It rejects public development interfaces, public runtime DSOs,
DT_RPATH, absolute/escaping runtime paths, invalid private links and ELF files
placed in development metadata directories. Dirty tests explicitly allow public
SONAME symlinks to private runtime libraries; normal tests do not. Imported
binaries retain their existing `--skip-runpath-check` exceptions.

Bootstrap recipes are built with package tests skipped. Run all installed recipe
tests after selfhost completes; earlier stages receive stage closure and runtime
smoke checks. Ordinary packages run their installed tests immediately. Test
actual pkg-config/CMake consumers, host-default discovery, and relative RUNPATH
after installation at a different prefix. Unit and render checks alone do not
establish that the whole bootstrap works.

See [native-private-install-dirs.md](native-private-install-dirs.md) for this
experiment's investigation and validation record. Earlier policies and their
results remain historical records in the other layout audit documents.
