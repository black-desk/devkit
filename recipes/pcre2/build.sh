#!/usr/bin/env bash
set -euxo pipefail

: "${PCRE2_VERSION:?rattler-build must provide PCRE2_VERSION}"
: "${SYSROOT_TRIPLET:?rattler-build must provide SYSROOT_TRIPLET}"

: "${BUILD_PREFIX:?}"
: "${PREFIX:?}"
export SYSROOT="${BUILD_PREFIX}/${SYSROOT_TRIPLET:-x86_64-pc-linux-gnu}/sysroot"
export CC="${BUILD_PREFIX}/bin/clang"
export CXX="${BUILD_PREFIX}/bin/clang++"
DEVKIT_FLAGS="--no-default-config --config=${BUILD_PREFIX}/share/devkit/clang.cfg"
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
export CXXFLAGS="${CFLAGS}"
export CPPFLAGS="${DEVKIT_FLAGS}"
export LDFLAGS="${DEVKIT_FLAGS} --ld-path=${BUILD_PREFIX}/bin/ld.lld -L${PREFIX}/lib/devkit/lib -L${PREFIX}/lib -Wl,-rpath-link,${PREFIX}/lib"
test -d "${SYSROOT}"
test -x "${CC}"

# Match forge's complete interfaces and use upstream's relocatable CMake exports.
# libedit supplies pcre2test's readline interface without another readline library.
cmake -S . -B build -G Ninja \
  -DCMAKE_PREFIX_PATH="${PREFIX}/lib/devkit" \
  -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=OFF \
  '-DCMAKE_INSTALL_RPATH=$ORIGIN:$ORIGIN/../lib' \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_INSTALL_LIBDIR=lib \
  -DCMAKE_INSTALL_INCLUDEDIR="lib/devkit/include/pcre2-${PCRE2_VERSION}" \
  -DCMAKE_C_COMPILER="${CC}" \
  -DCMAKE_C_FLAGS="${CFLAGS} -O3" \
  -DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}" \
  -DCMAKE_SHARED_LINKER_FLAGS="${LDFLAGS}" \
  -DCMAKE_BUILD_RPATH="${PREFIX}/lib" \
  -DCMAKE_FIND_ROOT_PATH="${PREFIX};${SYSROOT}" \
  -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
  -DCMAKE_DISABLE_FIND_PACKAGE_Readline=ON \
  -DBUILD_SHARED_LIBS=ON -DBUILD_STATIC_LIBS=ON \
  -DPCRE2_BUILD_PCRE2_8=ON -DPCRE2_BUILD_PCRE2_16=ON -DPCRE2_BUILD_PCRE2_32=ON \
  -DPCRE2_SUPPORT_JIT=ON -DPCRE2_SUPPORT_UNICODE=ON \
  -DPCRE2_BUILD_PCRE2GREP=ON -DPCRE2_BUILD_TESTS=ON \
  -DPCRE2_SUPPORT_LIBZ=ON -DPCRE2_SUPPORT_LIBBZ2=ON \
  -DPCRE2_SUPPORT_LIBEDIT=ON -DPCRE2_SUPPORT_LIBREADLINE=OFF \
  -DZLIB_INCLUDE_DIR="${PREFIX}/lib/devkit/include/zlib-1.3.2" \
  -DZLIB_LIBRARY="${PREFIX}/lib/devkit/lib/libz.so" \
  -DBZIP2_INCLUDE_DIR="${PREFIX}/lib/devkit/include/bzip2-1.0.8" \
  -DBZIP2_LIBRARY_RELEASE="${PREFIX}/lib/devkit/lib/libbz2.so" \
  -DEDITLINE_INCLUDE_DIR="${PREFIX}/lib/devkit/include/libedit-3.1.20260512/editline" \
  -DEDITLINE_LIBRARY="${PREFIX}/lib/devkit/lib/libedit.so"
cmake --build build --parallel "${CPU_COUNT}"
ctest --test-dir build --output-on-failure --parallel "${CPU_COUNT}"
cmake --install build

cat >"${SRC_DIR}/devkit-consumer.c" <<'EOF'
#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>

#include <stdio.h>

int main(void) {
  int error_code;
  PCRE2_SIZE error_offset;
  pcre2_code *code = pcre2_compile(
    (PCRE2_SPTR)"devkit", PCRE2_ZERO_TERMINATED, 0,
    &error_code, &error_offset, NULL
  );
  if (code == NULL) {
    return 1;
  }
  pcre2_code_free(code);
  puts("pcre2");
  return 0;
}
EOF

"${CC}" \
  ${CFLAGS} ${LDFLAGS} -Wl,-rpath,"${PREFIX}/lib" \
  -I"${PREFIX}/lib/devkit/include/pcre2-${PCRE2_VERSION}" \
  "${SRC_DIR}/devkit-consumer.c" \
  "${PREFIX}/lib/libpcre2-8.so" \
  -o "${SRC_DIR}/devkit-consumer"

env -u LD_LIBRARY_PATH -u LD_PRELOAD "${SRC_DIR}/devkit-consumer"

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
libraries = [path for stem in ['pcre2-8', 'pcre2-16', 'pcre2-32', 'pcre2-posix'] for path in (prefix / "lib").glob("lib" + stem + ".*")]
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
import re
# Change only location variables; upstream Libs/Requires retain their generated dependencies.
for name in ['libpcre2-8', 'libpcre2-16', 'libpcre2-32', 'libpcre2-posix']:
    path = prefix / "lib/pkgconfig" / (name + ".pc")
    target = dev / "lib/pkgconfig" / path.name
    target.parent.mkdir(parents=True, exist_ok=True)
    if path.is_file():
        assert not target.exists(), target
        shutil.move(str(path), target)
    assert target.is_file(), target
    text = target.read_text()
    values = {"prefix": "${pcfiledir}/../..", "exec_prefix": "${prefix}",
              "libdir": "${prefix}/lib", "includedir": "${prefix}/include/pcre2-10.49"}
    lines = text.splitlines(keepends=True)
    for key, value in values.items():
        matches = [i for i, line in enumerate(lines) if re.match(r"^" + key + r"\s*=", line)]
        if matches:
            assert len(matches) == 1, (target, key)
            lines[matches[0]] = key + "=" + value + "\n"
        elif key == "prefix":
            lines.insert(0, key + "=" + value + "\n")
    text = "".join(lines)
    # Recorded input prefixes become metadata-relative paths, preserving library order.
    text = text.replace(str(prefix) + "/lib/devkit", "${prefix}")
    text = text.replace(str(prefix) + "/lib", "${libdir}")
    text = text.replace(str(prefix) + "/include", "${includedir}")
    target.write_text(text)
# A moved export's computed _IMPORT_PREFIX/PACKAGE_PREFIX_DIR now denotes lib/devkit.
for name in ['pcre2']:
    source = prefix / "lib/cmake" / name
    target = dev / "lib/cmake" / name
    target.parent.mkdir(parents=True, exist_ok=True)
    if source.exists():
        assert not target.exists(), target
        shutil.move(str(source), target)
    assert target.is_dir(), target
    for path in target.rglob("*.cmake"):
        text = path.read_text()
        for variable in ["_IMPORT_PREFIX", "PACKAGE_PREFIX_DIR"]:
            text = text.replace("${" + variable + "}/lib/devkit/", "${" + variable + "}/")
            text = text.replace("${" + variable + "}/bin/", "${" + variable + "}/../../bin/")
        runtime = "${CMAKE_CURRENT_LIST_DIR}/" + os.path.relpath(prefix, path.parent)
        text = text.replace(str(prefix), runtime)
        path.write_text(text)
source = prefix / "bin/pcre2-config"
path = prefix / "libexec/pcre2/bin/pcre2-config"
path.parent.mkdir(parents=True, exist_ok=True)
shutil.move(str(source), path)
text = path.read_text()
text = re.sub(r"(?m)^prefix=.*$", 'prefix="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"', text, count=1)
text = re.sub(r"(?m)^exec_prefix=.*$", 'exec_prefix=${prefix}', text, count=1)
text = text.replace(str(prefix) + '/lib/devkit', '${prefix}/lib/devkit')
text = text.replace(str(prefix) + '/lib', '${prefix}/lib/devkit/lib')
text = text.replace(str(prefix) + '/include', '${prefix}/lib/devkit/include/pcre2-10.49')
text = text.replace(str(prefix), '${prefix}')
text = text.replace('${prefix}/include', '${prefix}/lib/devkit/include/pcre2-10.49')
text = text.replace('${exec_prefix}/lib', '${exec_prefix}/lib/devkit/lib')
path.write_text(text)
PYCODE
