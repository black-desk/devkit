#!/usr/bin/env bash
# Check runtime origin through developer link aliases and explicit dlopen.
set -euo pipefail
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"
mkdir -p prefix/lib/devkit/lib prefix/bin
printf 'int dependency(void) { return 42; }\n' >dependency.c
printf 'extern int dependency(void); int api(void) { return dependency(); }\n' >api.c
cat >main.c <<'C'
#include <stdio.h>
extern int api(void);
int main(void) { return api() == 42 ? 0 : 1; }
C
cat >load.c <<'C'
#include <dlfcn.h>
#include <stdio.h>
int main(int argc, char **argv) {
  void *p = dlopen(argv[1], RTLD_NOW);
  if (!p) { fprintf(stderr, "%s\n", dlerror()); return 1; }
  int (*api)(void) = dlsym(p, "api");
  return !api || api() != 42;
}
C
clang -shared -fPIC dependency.c -Wl,-soname,libdevkit_probe_dependency.so.1 -o prefix/lib/libdevkit_probe_dependency.so.1
clang -shared -fPIC api.c prefix/lib/libdevkit_probe_dependency.so.1 \
  -Wl,-soname,libdevkit_probe_api.so.1 '-Wl,-rpath,$ORIGIN' -o prefix/lib/libdevkit_probe_api.so.1
ln -sfn ../../libdevkit_probe_api.so.1 prefix/lib/devkit/lib/libdevkit_probe_api.so
ln -sfn ../../libdevkit_probe_api.so.1 prefix/lib/devkit/lib/libdevkit_probe_api.so.1
clang main.c prefix/lib/devkit/lib/libdevkit_probe_api.so \
  -Wl,-rpath-link,"$PWD/prefix/lib" '-Wl,-rpath,$ORIGIN/../lib' -o prefix/bin/probe
clang load.c -ldl -o load
readelf -d prefix/bin/probe
readelf -d prefix/lib/libdevkit_probe_api.so.1
env -u LD_LIBRARY_PATH -u LD_PRELOAD prefix/bin/probe
env -u LD_LIBRARY_PATH -u LD_PRELOAD ./load "$PWD/prefix/lib/libdevkit_probe_api.so.1"
if env -u LD_LIBRARY_PATH -u LD_PRELOAD ./load "$PWD/prefix/lib/devkit/lib/libdevkit_probe_api.so"; then
  printf 'unexpected success for dlopen alias\n' >&2
  exit 1
else
  printf 'Expected: dlopen through development alias cannot find neighbor dependency\n'
fi
# A consumer whose runtime search path points at the link interfaces loads the
# API through the alias too. This also models CMake's automatic build RUNPATH.
clang main.c prefix/lib/devkit/lib/libdevkit_probe_api.so \
  -Wl,-rpath-link,"$PWD/prefix/lib" '-Wl,-rpath,$ORIGIN/../lib/devkit/lib' \
  -o prefix/bin/hidden-runpath-probe
if env -u LD_LIBRARY_PATH -u LD_PRELOAD prefix/bin/hidden-runpath-probe; then
  printf 'unexpected success with development-only RUNPATH\n' >&2
  exit 1
fi
printf 'Expected: development-only RUNPATH cannot find neighbor dependency\n'
mv prefix relocated
env -u LD_LIBRARY_PATH -u LD_PRELOAD relocated/bin/probe
