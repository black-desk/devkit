# Development files and runtime discovery

The channel's tools default to host development files. Recipes explicitly opt
into channel development files. This is a discovery policy, not ELF isolation:
we do not prohibit the loader from searching host directories.

## Layout

```text
<prefix>/bin/                       tools
<prefix>/lib/libfoo.so.1.2.3         actual runtime library
<prefix>/lib/libfoo.so.1             runtime SONAME link
<prefix>/lib/ossl-modules/legacy.so   runtime plugin, unchanged
<prefix>/lib/devkit/include/foo-1.2.3/foo.h
<prefix>/lib/devkit/lib/libfoo.a
<prefix>/lib/devkit/lib/libfoo.so -> ../../libfoo.so.1
<prefix>/lib/devkit/lib/libfoo.so.1 -> ../../libfoo.so.1
<prefix>/lib/devkit/lib/libfoo.so.1.2.3 -> ../../libfoo.so.1.2.3
<prefix>/lib/devkit/lib/pkgconfig/foo.pc
<prefix>/lib/devkit/lib/cmake/foo/FooConfig.cmake
```

Keep versioned header roots and upstream inner header layouts. Runtime modules
loaded with dlopen are not development linker interfaces and stay in their
runtime locations. Classify files by purpose, not merely their `.so` suffix.
Provide relative aliases for versioned libraries as well as the unversioned
linker entry so upstream CMake exports can refer to their original filenames.
Real runtime library files are not duplicated.

The development prefix is `<prefix>/lib/devkit`. CMake configuration directories
may use `lib/cmake` or `share/cmake` beneath it, matching upstream installation.
Metadata and aliases must remain usable after relocation.

## Recipe discovery

Use `CMAKE_PREFIX_PATH=<prefix>/lib/devkit` and
`PKG_CONFIG_LIBDIR=<prefix>/lib/devkit/lib/pkgconfig`. Prefer upstream CONFIG
packages; `CMAKE_FIND_PACKAGE_PREFER_CONFIG=ON` changes normal find_package
ordering when appropriate. Keep explicit variables for Find modules that need
versioned header paths. Find modules do not universally read pkg-config:
FindZLIB, for example, searches headers and libraries directly.

The need to describe versioned header directories predates the hidden prefix.
Use upstream configuration interfaces where available. Patch consumer/Find logic
or pass exact paths where needed rather than abandoning header isolation. Zlib's
CMake build installs both CONFIG packages and pkg-config metadata.

## Runtime paths

Development library paths are link-time interfaces, not runtime search paths.
Executables and libraries must load libraries from public runtime directories.
Otherwise glibc can calculate a loaded library's $ORIGIN from the development
alias directory and fail to find its neighboring dependencies.

Prefer build-system support to write RUNPATH during linking/installing. CMake
build/test artifacts may use absolute public input-library paths; installed
artifacts use target-appropriate relative paths, such as `$ORIGIN/../lib` for
bin tools and `$ORIGIN` for public lib libraries. Disable automatic addition of
external link directories to install RUNPATH. CMake's automatic build RUNPATH
also needs attention when imported targets point to development aliases. Do not
assume BUILD_RPATH_USE_ORIGIN replaces hidden paths with public paths: it only
makes eligible build-tree entries relative.

For Make/Autotools, use supported link/install variables and upstream relinking;
account for shell and Make escaping separately. Meson supports target
build_rpath and install_rpath. Cargo has linker arguments. Do not rewrite
installed ELF files merely to normalize outputs that their build systems can
produce correctly. Any necessary post-link exception must identify the
unsupported behavior and why native configuration cannot handle it.

## Validation and rollout

Validate host-default and explicit-channel discovery, versioned headers, CONFIG
and pkg-config consumers, shared/static linkage, indirect dependencies, plugins,
and relocation. A SONAME link must remain in public lib as well as the actual
library file. Tests run without global loader overrides; existing scoped preload
for upstream Rust tools is unchanged.

Keep the same recipe across bootstrap generations. Do not remove enabled
features or change the seed to simplify migration. Compiler runtime resources
need explicit handling: they are not generic user library discovery files. Full
validation requires dirty, result, selfhost and independent smoke stages. Local
focused checks do not substitute for that CI bootstrap.

Retired GCC packages can be removed independently once the Clang generation has
published successfully and no retained package depends on them. Do not delete
llvm-libgcc or compiler runtime resources as part of that cleanup.

## Packaging implementation

`stage-development.py` stages development interfaces after upstream
installation. Recipes call it with `--all` to select newly installed headers,
top-level linker interfaces/archives and metadata; installed input files are
excluded using conda-meta ownership records. Runtime library files and SONAME
links stay in public lib; relative development aliases preserve exported
filenames. This is a packaging operation, not a shared compiler/environment
setup script.

Generic staging does not traverse plugin/resource directories. CMake-installed
object-library files under `lib/objects-*` are development interfaces and move
with their exported targets. An unversioned runtime ELF in public lib is
rejected for explicit review rather than silently moving a runtime interface.
Exported CMake executable locations point back to public bin, so LLVM and PCRE2
need no overlapping ownership of a hidden bin alias. Configured absolute CMake
paths become relative to the configuration file. Compiler resources remain in
their upstream locations.

Native RUNPATH configuration is implemented for CMake recipes, Cargo tools,
pkgconf/Meson, Git, Make, bzip2, keyutils and lz4. Libtool projects that use
-no-install for build tests and projects with one shared link setting for
multiple installation depths retain annotated post-link exceptions. These
exceptions remain visible work, not a claim that Make or Autotools universally
lack support.

Gettext's private runtime SONAMEs include the version before the `.so` suffix
(`libgettextlib-0.25.1.so` and `libgettextsrc-0.25.1.so`). Its recipe explicitly
marks those inspected runtime filenames; generic `libgettextlib.so` and
`libgettextsrc.so` links are still hidden. The preloadable libintl module stays
in place. The installed-stage smoke check rejects public developer interfaces
and absolute/development-directory runtime paths.

`llvm-config` receives a source patch to detect the installed hidden developer
prefix, preserving build-tree and ordinary upstream behavior. Its package tests
check include, library and CMake-directory output. The complete migration bumps
all outputs selected by the affected planner, including unchanged data/tool
recipes that the global smoke-check change requires rebuilding.

Pkg-config normalization accepts whitespace around variable assignments and
defines a missing prefix. ICU's Make metadata separates hidden header/linker
paths from public runtime paths. Config helpers keep emitted RUNPATH flags on
public lib. LZO retains both its upstream flat include spelling and the
conventional `lzo/` spelling.

Libtool can discard bare absolute shared-library inputs. Libxml2 passes its
exact zlib interface through `-Wl,PATH`, as curl already does, and tests the
installed `DT_NEEDED` entry and an independent consumer. See
[the per-package review](development-prefix-audit.md) for focused validation and
the remaining CI boundary.
