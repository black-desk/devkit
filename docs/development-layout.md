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

LLVM runtime development interfaces use this same `lib/devkit/lib` directory. Do
not create an additional `llvm-runtime` link directory or add it to linker
search flags: its entries duplicated the interfaces already present in the
parent directory. Validation against the successful selfhost CI artifact
compared shared libc++, static libc++/libc++abi, and GCC-compatible unwind
linkage before and after removal, then after relocating the environment. Linker
inputs remained identical, runtime probes passed, and
default-host/explicit-channel Clang policy and installed-package layout checks
passed.

## Installing development files and generating metadata

Use existing upstream installation options when they express the desired layout
without changing dependency generation. Otherwise, install normally and keep the
necessary file moves and metadata path edits in that recipe's own build script.
Preserve upstream-generated dependency lists, enabled features and link order;
layout changes must not replace them with manually enumerated libraries.

At this stage, keep this packaging logic local to each recipe, even when there
is repetition. Do not add shared staging rules or extract new common helpers.
Once the requested channel package inventory is complete and the actual cases
are understood, review common patterns for possible extraction. Prefer explicit
moves and targeted edits with checked expectations over broad substitutions
across unrelated files. Keep runtime libraries, SONAME aliases, plugins and
compiler/language resources in their public upstream locations. Adjust relative
symlink targets when moving development interfaces.

Validate the final archive layout and ELF attributes, then installed metadata,
consumer compilation/linking and relocation. A successful build alone does not
prove that a moved CMake export or pkg-config file still describes usable paths.
Conda prefix replacement handles recorded absolute environment prefixes; it does
not repair relative paths whose meaning changed when a file moved.

This policy supersedes the earlier preference for patching upstream install
rules/templates before building. The previous implementation and validation
history remain in [native-install-audit.md](native-install-audit.md). The new
per-recipe migration and checks are tracked in
[recipe-local-layout-audit.md](recipe-local-layout-audit.md).

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

## Package checks

`scripts/packaging/check-package.py PREFIX --package NAME` checks only files
owned by that installed package, using its `conda-meta` file list. Native
payload recipes copy the standalone checker as a source input and archive it
with a dedicated recipe script test. Metadata-only recipes and compatibility
outputs need no separate ELF audit. Python 3 and readelf are runner tooling,
like the tools already used by package tests; they do not add runtime or seed
dependencies.

The checker rejects DT_RPATH, absolute or working-directory-relative search
paths, empty search entries, paths escaping the installed prefix, and runtime
paths resolving into `lib/devkit`. RUNPATH entries must start with `$ORIGIN` or
`${ORIGIN}`; ELFs without a search path are allowed. It also checks public
development-file locations, relocatable/non-dangling development symlinks, and
that dynamic runtime ELFs are not stored in the hidden development prefix. The
explicit `--skip-runpath-check` option disables only RPATH/RUNPATH policy checks
for imported binaries. Python, rustup, Go and b4 use this option to retain their
upstream/runtime packaging choices. In b4, imported manylinux wheels retain
auditwheel's RPATHs for their bundled native dependencies in the private Python
environment. File ownership, development layout and symlink checks, and the ban
on runtime ELFs in `lib/devkit` remain enabled. Default invocations, including
completed bootstrap-prefix audits, remain strict. Existing Python runtime/venv
tests, rustup loader/runtime tests and b4 native module/relocation tests still
run. The skipped check is omitted from the success message.

Dependencies are present during installed tests, so a development link into a
separate runtime package is valid. Missing ownership records fail the audit.

The sysroot recipe does not run this checker: its Rocky RPM ELFs are original
target-system inputs, not channel-built runtime outputs. Completed-prefix checks
likewise skip the canonical and seed-triplet sysroot trees. Archived test inputs
under `etc/conda/test-files` are excluded; copying the same ELF into an actual
runtime location does not exempt it.

Bootstrap remains a stage-level unit: dirty/result completion checks install and
audit the completed channel; selfhost package recipe tests and runtime smoke
checks run after its entire stage, in the independent test job. No per-package
archive check or early installed test is added to bootstrap. Ordinary packages
run their recipe tests immediately after packaging. Installed-consumer probes
are compiled and run together in those recipe tests, including deferred
bootstrap recipe tests. Archive their recipe-owned source files, declare the
channel compiler/sysroot as test inputs, and select `share/devkit/clang.cfg`
explicitly. Do not carry uninstalled build-stage probe executables into a test
environment or create scratch library links to keep such executables runnable. A
test-only consumer may use an absolute RUNPATH to that environment's public lib
directory; it is not an installed package ELF. Build-only consumer checks that
compile and run in the same phase are a separate case. The completed-channel
entry point, `scripts/check-development-layout.py`, delegates to this same
checker without `--package` to audit the entire installed prefix.

## Packaging implementation

`scripts/packaging/` contains the shared recipe packaging utilities. Recipes
copy only the required scripts into their `devkit-build/` source directory; they
do not import the clang recipe directory. Clang continues to install these
staging/relocation utilities under `share/devkit` in its package. Changes to
shared packaging utilities are global packaging inputs in the affected-build
planner, so they trigger a full channel rebuild. `finalize-elf.py` implements
the annotated post-link RUNPATH exceptions described above.

`scripts/packaging/stage-development.py` stages development interfaces after
upstream installation. Recipes call it with `--all` to select newly installed
remaining top-level linker interfaces/archives; installed input files are
excluded using conda-meta ownership records. Native headers and metadata already
installed under the development prefix are left untouched. Runtime library files
and SONAME links stay in public lib; relative development aliases preserve
exported filenames. This is a packaging operation, not a shared
compiler/environment setup script.

Generic staging does not traverse plugin/resource directories. CMake
object-library files are development interfaces; JsonCpp now installs them
directly under the hidden library directory with matching exports. The generic
fallback also understands legacy `lib/objects-*` inputs. An unversioned runtime
ELF in public lib is rejected for explicit review rather than silently moving a
runtime interface. Exported CMake executable locations point back to public bin,
so LLVM and PCRE2 need no overlapping ownership of a hidden bin alias.
Configured absolute CMake paths become relative to the configuration file.
Compiler resources remain in their upstream locations.

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
