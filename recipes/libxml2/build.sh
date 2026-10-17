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
export LDFLAGS="${DEVKIT_FLAGS} --ld-path=${BUILD_PREFIX}/bin/ld.lld -L${PREFIX}/lib/devkit/lib -L${PREFIX}/lib -Wl,-rpath-link,${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib"
test -d "${SYSROOT}"
test -x "${CC}"
unset LD_LIBRARY_PATH LD_PRELOAD
unset PYTHON
export CPPFLAGS="${CPPFLAGS} -I${PREFIX}/lib/devkit/include/libiconv-1.18 -I${PREFIX}/lib/devkit/include/zlib-1.3.2"
export LDFLAGS="${LDFLAGS} -lgcc_s -liconv -Wl,-rpath,${SRC_DIR}/.libs"
export PKG_CONFIG="${BUILD_PREFIX}/bin/pkgconf"
export PKG_CONFIG_LIBDIR="${PREFIX}/lib/devkit/lib/pkgconfig"
unset PKG_CONFIG_PATH
cp "${BUILD_PREFIX}/share/gnuconfig/config.guess" config.guess
cp "${BUILD_PREFIX}/share/gnuconfig/config.sub" config.sub
# FTP and LZMA were removed upstream before/in 2.15; the forge recipe's old
# options no longer enable them. --with-tls means thread-local storage.
./configure --prefix="${PREFIX}" --includedir="${PREFIX}/lib/devkit/include/libxml2-${LIBRARY_VERSION}" --with-iconv --with-zlib --with-icu \
  --with-legacy --with-python=no --with-tls --enable-static=no \
  --with-schematron=yes
# Libtool's -no-install builds executables with build-tree RUNPATH instead of
# loader-environment shell wrappers. Finalization replaces that RUNPATH.
make -j"${CPU_COUNT}" AM_LDFLAGS=-no-install
if [[ "${DEVKIT_RUN_TESTS:-1}" == 1 ]]; then
  make check AM_LDFLAGS=-no-install
fi
make install AM_LDFLAGS=-no-install \
  pkgconfigdir="${PREFIX}/lib/devkit/lib/pkgconfig" \
  cmakedir="${PREFIX}/lib/devkit/lib/cmake/libxml2"
rm -f "${PREFIX}/lib/libxml2.la"
# Post-link exception: Libtool -no-install avoids global loader wrappers for upstream tests but installs build-tree RUNPATH unchanged.
# TODO: replace with target-specific upstream install/relink support.
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"

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
libraries = [path for stem in ['xml2'] for path in (prefix / "lib").glob("lib" + stem + ".*")]
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
for name in ['libxml-2.0']:
    path = prefix / "lib/pkgconfig" / (name + ".pc")
    target = dev / "lib/pkgconfig" / path.name
    target.parent.mkdir(parents=True, exist_ok=True)
    if path.is_file():
        assert not target.exists(), target
        shutil.move(str(path), target)
    assert target.is_file(), target
    text = target.read_text()
    values = {"prefix": "${pcfiledir}/../..", "exec_prefix": "${prefix}",
              "libdir": "${prefix}/lib", "includedir": "${prefix}/include/libxml2-2.15.4"}
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
for name in ['libxml2']:
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
headers = dev / "include/libxml2-2.15.4"
shutil.move(str(headers / "libxml2/libxml"), headers / "libxml")
(headers / "libxml2").rmdir()
path = dev / "lib/pkgconfig/libxml-2.0.pc"
text = path.read_text().replace('-I${includedir}/libxml2', '-I${includedir}')
path.write_text(text)
path = dev / "lib/cmake/libxml2/libxml2-config.cmake"
text = path.read_text().replace('/include/libxml2-2.15.4/libxml2', '/include/libxml2-2.15.4')
path.write_text(text)
path = prefix / "bin/xml2-config"
text = path.read_text()
text = re.sub(r'(?m)^prefix=.*$', 'prefix="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"', text, count=1)
text = re.sub(r'(?m)^exec_prefix=.*$', 'exec_prefix=${prefix}', text, count=1)
text = re.sub(r'(?m)^includedir=.*$', 'includedir=${prefix}/lib/devkit/include/libxml2-2.15.4', text, count=1)
text = re.sub(r'(?m)^libdir=.*$', 'libdir=${prefix}/lib/devkit/lib', text, count=1)
text = text.replace(str(prefix), '${prefix}')
text = text.replace('-I${includedir}/libxml2', '-I${includedir}')
text = text.replace('includedir=$prefix/include', 'includedir=$prefix/lib/devkit/include/libxml2-2.15.4')
path.write_text(text)
PYCODE
