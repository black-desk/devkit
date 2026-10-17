#!/usr/bin/env bash
set -euxo pipefail

: "${SYSROOT_TRIPLET:?rattler-build must provide sysroot_triplet}"
: "${LIBCXX_VERSION:?rattler-build must provide LIBCXX_VERSION}"
SYSROOT="${BUILD_PREFIX}/${SYSROOT_TRIPLET}/sysroot"
CC="${BUILD_PREFIX}/bin/clang"
CXX="${BUILD_PREFIX}/bin/clang++"
if [[ "${SYSROOT_TRIPLET}" == x86_64-conda-linux-gnu ]]; then
  # Prepare the fresh seed build environment with unversioned driver names.
  ln -sfn clang-23 "${BUILD_PREFIX}/bin/clang"
  ln -sfn clang++-23 "${BUILD_PREFIX}/bin/clang++"
  GCC_INSTALL="${BUILD_PREFIX}/lib/gcc/x86_64-conda-linux-gnu/16.2.0"
  COMMON_FLAGS="--no-default-config --sysroot=${SYSROOT} --gcc-install-dir=${GCC_INSTALL} -O2 -fPIC --rtlib=compiler-rt"
else
  # Building libc++ itself must not inherit clang.cfg's installed libc++
  # include path: C wrapper include_next would select the old wrappers.
  COMMON_FLAGS="--no-default-config --sysroot=${SYSROOT} --gcc-toolchain=${BUILD_PREFIX}/share/devkit/no-gcc -O2 -fPIC --rtlib=compiler-rt"
fi
COMMON_FLAGS="--start-no-unused-arguments ${COMMON_FLAGS} --end-no-unused-arguments"
LINK_FLAGS="--ld-path=${BUILD_PREFIX}/bin/ld.lld --unwindlib=none -L${PREFIX}/lib/devkit/lib -L${PREFIX}/lib -Wl,-rpath-link,${SYSROOT}/lib64"

cmake -S "${SRC_DIR}/runtimes" -B build -G Ninja \
  -DCMAKE_PREFIX_PATH="${PREFIX}/lib/devkit" \
  -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=OFF \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_BUILD_RPATH="${PREFIX}/lib" \
  '-DCMAKE_INSTALL_RPATH=$ORIGIN' \
  -DCMAKE_C_COMPILER="${CC}" \
  -DCMAKE_CXX_COMPILER="${CXX}" \
  -DCMAKE_C_COMPILER_TARGET=x86_64-pc-linux-gnu \
  -DCMAKE_CXX_COMPILER_TARGET=x86_64-pc-linux-gnu \
  -DCMAKE_AR="${BUILD_PREFIX}/bin/llvm-ar" \
  -DCMAKE_RANLIB="${BUILD_PREFIX}/bin/llvm-ranlib" \
  -DCMAKE_FIND_ROOT_PATH="${SYSROOT};${PREFIX}" \
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
  -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
  -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY \
  -DCMAKE_C_FLAGS="${COMMON_FLAGS}" \
  -DCMAKE_CXX_FLAGS="${COMMON_FLAGS} -nostdinc++ -nostdlib++" \
  -DCMAKE_EXE_LINKER_FLAGS="${LINK_FLAGS}" \
  -DCMAKE_SHARED_LINKER_FLAGS="${LINK_FLAGS}" \
  -DCMAKE_MODULE_LINKER_FLAGS="${LINK_FLAGS}" \
  -DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi" \
  -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF \
  -DLIBCXX_INSTALL_INCLUDE_DIR="lib/devkit/include/libcxx-${LIBCXX_VERSION}/c++/v1" \
  -DLIBCXXABI_INSTALL_INCLUDE_DIR="lib/devkit/include/libcxx-${LIBCXX_VERSION}/c++/v1" \
  -DLIBCXX_INCLUDE_TESTS=OFF \
  -DLIBCXXABI_INCLUDE_TESTS=OFF \
  -DLIBCXX_USE_COMPILER_RT=ON \
  -DLIBCXXABI_USE_COMPILER_RT=ON \
  -DLIBCXXABI_USE_LLVM_UNWINDER=OFF \
  -DLIBCXXABI_HAS_GCC_S_LIB=ON

# USE_LLVM_UNWINDER=OFF means use the separately packaged system interface;
# its gcc_s name is supplied by llvm-libgcc, not the GNU implementation.
cmake --build build --parallel "${CPU_COUNT}"
cmake --install build

# Keep development layout handling in this recipe until channel coverage is complete.
python3 - <<'PYCODE'
import os
from pathlib import Path
import re
import shutil
prefix = Path(os.environ["PREFIX"])
dev = prefix / "lib/devkit"
(dev / "lib").mkdir(parents=True, exist_ok=True)
# Resolve every alias before removing any public linker symlinks.
libraries = [path for stem in ['c++', 'c++abi', 'c++experimental'] for path in (prefix / "lib").glob("lib" + stem + ".*")]
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
