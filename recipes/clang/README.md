# Compiler design

The channel uses Clang with LLVM binary tools, LLD, libc++ and compiler-rt to
build a self-hosting LLVM toolchain without GNU compiler or runtime packages in
the final generation. The seed's GNU development files are bootstrap inputs.
Clang, LLVM tools and LLD build from the same source revision to keep their
interfaces aligned; the early runtime recipes break the bootstrap dependency
cycle.

## Host defaults and explicit channel builds

Installing a compiler should not silently select the channel's libraries for
ordinary host projects. `host.cfg` limits GCC development discovery to `/usr`;
the driver's defaults retain host libstdc++ and the host linker. The compiler
executable itself links channel runtimes independently of the runtime selected
for programs it produces.

Channel recipes explicitly disable default configuration and load `clang.cfg`.
This selects the channel sysroot and LLVM runtime interfaces without discovering
host GCC. `<CFGDIR>` paths keep that configuration relocatable. Output RUNPATH
remains the consuming recipe's responsibility because executable installation
depths differ.

The old `GCC_INSTALL_PREFIX` CMake setting was rejected by Clang as deprecated.
Separate driver configurations express the two policies without baking a channel
sysroot into every user invocation. `--ld-path` selects LLD explicitly: absolute
`-fuse-ld` produced a deprecation warning that broke unrelated configure probes
using `-Werror`.

## Runtime ownership and headers

`llvm-libgcc` builds the initial unwinder, builtins and CRT without depending on
libc++. User-facing compiler-rt runtimes build here after libc++ exists; putting
them into the early runtime package would introduce a dependency cycle. The
resource-directory link shares their installation directory without duplicating
builtins or CRT ownership.

The private libc++ used by libFuzzer must not inherit the installed libc++
header path from `clang.cfg`. Two sets of C wrapper headers intercept
`include_next` and hide system declarations. `build-runtimes.sh` and its source
patch give the private build clean flags while preserving upstream's hermetic
libc++ behavior.

## Feature baseline requiring care

The pinned seed enables compression/XML dependencies, RTTI and default PIE;
those features must not be dropped merely to shrink the bootstrap closure.
LIBEDIT and TERMINFO were also disabled in the inspected seed baseline. Before
changing those options, check whether the pinned LLVM implements them and which
shipped tools use them; option names alone do not establish missing
functionality.

See the shared [installation policy](../../docs/development-layout.md) for
header isolation and runtime search rules. Package definitions and tests remain
in `recipe.yaml` and the build scripts.
