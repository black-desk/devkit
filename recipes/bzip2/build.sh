#!/usr/bin/env bash
set -euxo pipefail

# Bootstrap skips suites in dirty/result; standalone builds run them by default.
case "${DEVKIT_RUN_TESTS:-1}" in
  0 | 1) ;;
  *)
    printf 'error: DEVKIT_RUN_TESTS must be 0 or 1\n' >&2
    exit 1
    ;;
esac
: "${BUILD_PREFIX:?}"
: "${PREFIX:?}"
export SYSROOT="${BUILD_PREFIX}/${SYSROOT_TRIPLET:-x86_64-pc-linux-gnu}/sysroot"
export CC="${BUILD_PREFIX}/bin/clang"
export CXX="${BUILD_PREFIX}/bin/clang++"
if [[ "${SYSROOT_TRIPLET:-}" == x86_64-conda-linux-gnu ]]; then
  # Prepare the fresh seed build environment with unversioned driver names.
  ln -sfn clang-23 "${BUILD_PREFIX}/bin/clang"
  ln -sfn clang++-23 "${BUILD_PREFIX}/bin/clang++"
  DEVKIT_FLAGS="--start-no-unused-arguments --no-default-config --sysroot=${SYSROOT} --gcc-install-dir=${BUILD_PREFIX}/lib/gcc/x86_64-conda-linux-gnu/16.2.0 --rtlib=compiler-rt --unwindlib=none --end-no-unused-arguments"
else
  DEVKIT_FLAGS="--no-default-config --config=${BUILD_PREFIX}/share/devkit/clang.cfg"
fi
export AR="${BUILD_PREFIX}/bin/llvm-ar"
export RANLIB="${BUILD_PREFIX}/bin/llvm-ranlib"
export NM="${BUILD_PREFIX}/bin/llvm-nm"
export STRIP="${BUILD_PREFIX}/bin/llvm-strip"
export OBJCOPY="${BUILD_PREFIX}/bin/llvm-objcopy"
export OBJDUMP="${BUILD_PREFIX}/bin/llvm-objdump"
export READELF="${BUILD_PREFIX}/bin/llvm-readelf"
export LD="${BUILD_PREFIX}/bin/ld.lld"
export PATH="${BUILD_PREFIX}/bin:${PATH}"
export CFLAGS="${DEVKIT_FLAGS} -O2 -fPIC"
if [[ "${SYSROOT_TRIPLET:-}" == x86_64-conda-linux-gnu ]]; then
  export CXXFLAGS="${CFLAGS} --start-no-unused-arguments -stdlib=libc++ -nostdinc++ -isystem ${PREFIX}/lib/devkit/include/libcxx-23.1.3/c++/v1 --end-no-unused-arguments"
else
  # clang.cfg already selects libc++ headers. Adding a second copy from the
  # native host prefix breaks C wrapper include_next. Both prefixes select
  # the same libc++ package from the completed input generation.
  export CXXFLAGS="${CFLAGS}"
fi
export CPPFLAGS="${DEVKIT_FLAGS}"
# Make expands $$ once; shell quotes preserve the literal loader token.
export LDFLAGS="${DEVKIT_FLAGS} --ld-path=${BUILD_PREFIX}/bin/ld.lld -L${PREFIX}/lib/devkit/lib -L${PREFIX}/lib -Wl,-rpath-link,${PREFIX}/lib"
test -d "${SYSROOT}"
test -x "${CC}"
NATIVE_LDFLAGS="${LDFLAGS} -Wl,--enable-new-dtags,-rpath,'\$\$ORIGIN:\$\$ORIGIN/../lib'"
export CFLAGS="${CFLAGS} -Wall -Winline -D_FILE_OFFSET_BITS=64"
# Build libraries/tools separately from the upstream fixture target.
make -j"${CPU_COUNT}" CC="${CC}" AR="${AR}" RANLIB="${RANLIB}" \
  CFLAGS="${CFLAGS}" LDFLAGS="${NATIVE_LDFLAGS}" libbz2.a bzip2 bzip2recover
if [[ "${DEVKIT_RUN_TESTS:-1}" == 1 ]]; then
  make test CC="${CC}" AR="${AR}" RANLIB="${RANLIB}" \
    CFLAGS="${CFLAGS}" LDFLAGS="${NATIVE_LDFLAGS}"
fi
make install PREFIX="${PREFIX}" \
  CC="${CC}" AR="${AR}" RANLIB="${RANLIB}" \
  CFLAGS="${CFLAGS}" LDFLAGS="${NATIVE_LDFLAGS}"
make -f Makefile-libbz2_so -j"${CPU_COUNT}" CC="${CC}" \
  CFLAGS="${CFLAGS}" LDFLAGS="${NATIVE_LDFLAGS}"
cp -a libbz2.so.1.0.8 libbz2.so.1.0 "${PREFIX}/lib/"
ln -s libbz2.so.1.0 "${PREFIX}/lib/libbz2.so"
# Exercise the shared-library executable before package relocation.
./bzip2-shared -dc sample1.bz2 >shared-result
cmp sample1.ref shared-result
# Stage only this package's development interfaces; preserve runtim# Keep development layout handling in this recipe until channel coverage is complete.
python3 - <<'PYCODE'
import os
from pathlib import Path
import re
import shutil
prefix = Path(os.environ["PREFIX"])
dev = prefix / "lib/devkit"
(dev / "lib").mkdir(parents=True, exist_ok=True)
(dev / "include/bzip2-1.0.8").mkdir(parents=True, exist_ok=True)
shutil.move(str(prefix / "include/bzlib.h"), dev / "include/bzip2-1.0.8/bzlib.h")
# Upstream bzip2 installs man pages under man rather than share/man.
(prefix / "share").mkdir(exist_ok=True)
shutil.move(str(prefix / "man"), prefix / "share/man")
# Resolve every alias before removing any public linker symlinks.
libraries = [path for stem in ['bz2'] for path in (prefix / "lib").glob("lib" + stem + ".*")]
shared = {path: path.resolve(strict=True) for path in libraries if ".so" in path.name and path.is_symlink()}
for path in libraries:
    target = dev / "lib" / path.name
    if path.name.endswith((".a", ".la")):
        assert not target.exists(), target
        if path.is_symlink():
            original = Path(os.path.abspath(path.parent / path.readlink()))
            if original in libraries:
                original = dev / "lib" / original.name
            target.symlink_to(os.path.relpath(original, target.parent))
            path.unlink()
        else:
            shutil.move(str(path), target)
        if target.suffix == ".la":
            target.write_text(re.sub(re.escape(str(prefix)) + r"/lib(?!/devkit)(?=/|['\s])", str(dev) + "/lib", target.read_text()))
    elif ".so" in path.name:
        if path in shared:
            runtime = shared[path]
            target.symlink_to(os.path.relpath(runtime, target.parent))
            if path.name.endswith(".so"):
                path.unlink()
        else:
            with path.open("rb") as stream:
                elf = stream.read(4) == b"\x7fELF"
            if not path.name.endswith(".so"):
                target.symlink_to(os.path.relpath(path, target.parent))
            else:
                assert not elf, ("unreviewed unversioned runtime ELF", path)
                shutil.move(str(path), target)
                target.write_text(target.read_text().replace(str(prefix) + "/lib/", str(dev) + "/lib/"))
PYCODE
