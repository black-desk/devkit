# Development prefix experiment

Local branch: `experiment/devkit-development-prefix`. The initial zlib
experiment has expanded into a channel-wide migration. The authoritative
decisions are in [development-layout.md](development-layout.md). The old CMake
discovery patch is removed; full bootstrap validation is delegated to PR CI.

The zlib recipe installs versioned headers under
`lib/devkit/include/zlib-1.3.2`, its static archive and unversioned linker
symlink under `lib/devkit/lib`, and metadata under `lib/devkit/lib/pkgconfig`.
Runtime libraries remain under `lib`. The linker symlink is relative:
`lib/devkit/lib/libz.so -> ../../libz.so.1`. The pkg-config prefix is relative
to `pcfiledir`.

Recipes opt into this layout with `PKG_CONFIG_LIBDIR` pointing at the hidden
metadata directory. For CMake, `CMAKE_PREFIX_PATH=<prefix>/lib/devkit` finds
linker interfaces, but built-in find modules generally do not search arbitrary
versioned header subdirectories. They also need `CMAKE_INCLUDE_PATH` or explicit
package include variables. This experiment deliberately preserves versioned
header directories rather than adding public header aliases.

## Focused validation

`scripts/experiments/check-development-prefix.sh PREFIX` uses an unpatched host
CMake and host pkgconf. It models CMake's own implicit installation prefix by
adding PREFIX to `CMAKE_SYSTEM_PREFIX_PATH`, then checks that default FindZLIB
selects host development files and explicit discovery selects the experimental
files. It builds and runs CMake and pkg-config consumers, checks the CMake
consumer's runtime zlib path, and builds a static consumer. Set
`PILOT_INSTALLED_CMAKE=1` and put PREFIX/bin first in PATH to instead check an
unpatched CMake physically installed into the prefix. This mode verifies its
CMAKE_ROOT and does not inject a simulated system prefix.

Locally, zlib 1.3.2 was compiled with host Clang using the recipe's configure,
install and layout commands. Upstream `make test` and the focused probe passed,
including after moving the entire installation directory. No conda package or
complete bootstrap was built. All build products remain outside the repository.

Additional checks used unpatched system CMake 3.28.3 copied with its module tree
into the pilot prefix. Its CMAKE_ROOT resolved to the copied tree. Default host
lookup, explicit channel lookup and consumer execution passed in this mode. This
validates the upstream search behavior, not the exact channel CMake build.

A separate zlib CMake installation under the development prefix passed all 18
upstream tests. Real runtime libraries were moved into public lib, public SONAME
links retained, and relative versioned-library aliases left in the development
lib directory. Without editing upstream exported targets, shared and static
CONFIG-mode consumers built and ran after relocation. CONFIG mode supplied the
versioned include directory without an extra include-path override.

`scripts/experiments/check-development-origin.sh` checks a shared library with a
unique SONAME dependency and `$ORIGIN` RUNPATH. Linking through a development
alias and loading through public lib works, including after relocation. Direct
dlopen of the development alias fails to find the neighbor dependency. Loading
through a development-only executable RUNPATH fails in the same way: glibc uses
the alias directory for the loaded library's origin.

CMake automatically adds imported-library directories to build RUNPATH. This can
introduce the hidden development directory as a runtime entry point. Recipes
must ensure build/test executables search public lib instead. In the focused
CONFIG consumer, `CMAKE_BUILD_WITH_INSTALL_RPATH=ON` with an explicit public-lib
`CMAKE_INSTALL_RPATH` worked. Installed package ELF files already get their
RUNPATH rewritten by finalize-elf.py, but that does not protect earlier build
tests. Runtime plugins remain in their original runtime locations.

## Migration validation status

All library recipes now stage development interfaces, and recipe consumers,
compiler configuration, package contents and metadata tests use the new paths.
Zlib now uses upstream CMake to retain both CONFIG and pkg-config interfaces.
Its parallel suite exposed a configure-fixture typo; the recipe carries a small
TODO-upstream patch rather than disabling those tests.

The native zlib build and staging commands passed all 18 upstream tests plus
shared/static pkg-config consumers. The pipeline suite includes three staging
checks for relocation, runtime-plugin retention and dependency-file ownership.
CMake package discovery tests now place their fixtures in the hidden prefix.
CMake/Cargo/Meson and selected Make recipes use native runtime paths; annotated
post-link exceptions remain for unsupported install/relink layouts.

No full local bootstrap was started. The PR must pass dirty, result, selfhost,
independent package smoke tests and ordinary builds before publication. Changes
to bootstrap recipes and compiler source snapshots force that full rebuild.

A focused rattler-build seed-mode build also passed the 18 upstream tests and
package-content checks. Its initial metadata test assumed Forge's pkgconf had a
pkg-config alias, which it does not. Zlib now invokes the provided pkgconf
command directly; the channel pkgconf recipe separately tests its pkg-config
alias. The corrected seed-mode run built zlib and libzlib and passed all
packaged tests.

Static aliases are retargeted during staging: libgcc.a can still refer to the
public compiler-rt resource directory, while libgcc_eh.a follows the moved
libunwind archive. The relocation regression check covers both cases. The
planner validates all 59 selected package outputs with a fresh revision.

The subsequent [per-package review](development-prefix-audit.md) records real
payload staging, exported-interface consumer tests and the corrections found
after the initial PR. It distinguishes those checks from complete producer
rebuilds, which remain the responsibility of bootstrap CI.
