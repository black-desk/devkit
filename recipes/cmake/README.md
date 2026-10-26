# Discovery and dependency choices

CMake must keep host package discovery as its default even when installed beside
channel libraries. Its Unix platform module infers a system prefix from
`CMAKE_ROOT`; moving CMake's own modules below `lib/devkit` would expose that
private prefix to implicit searches. Keep those modules under public `share`;
other resources can follow the private installation policy. Hiding development
interfaces avoids patching CMake's package-search implementation. Recipes opt in
explicitly and pass versioned include paths when Find modules cannot infer them.

External channel libraries make CMake's build/runtime dependency closure visible
to the package graph and independently rebuildable. Feature assertions prevent
missing dependencies from silently dropping the curses frontend, debugger or
archive backends. Dependency discovery stays within the selected host prefix and
sysroot rather than falling back to the build machine.

CMake's own build defaults to using install RPATH in the build tree. That caused
newly linked cmake/ctest to miss their input libraries before installation.
`CMAKE_BUILD_WITH_INSTALL_RPATH=OFF` keeps build and installation paths
separate; the native installer still writes relative RUNPATH.

## Historical bootstrap patch

The retained `bootstrap-exclude-ghs-generator.patch` only affects
`CMAKE_BOOTSTRAP`, while this recipe configures with previous-stage CMake. It
guards a generator include during that alternate bootstrap path and does not
affect the normal recipe build. Whether to remove it or explicitly support the
alternate path remains unresolved.
