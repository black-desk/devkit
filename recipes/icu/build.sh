#!/usr/bin/env bash
set -euxo pipefail
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
unset LD_LIBRARY_PATH LD_PRELOAD ICU_DATA
export CXXFLAGS="${CXXFLAGS} -std=c++17"
# ICU runs newly built tools through its upstream loader-environment wrappers.
# Keep build-tree library paths out of the exported linker configuration.
export LDFLAGS="${LDFLAGS} -lgcc_s"
cp "${BUILD_PREFIX}/share/gnuconfig/config.guess" source/config.guess
cp "${BUILD_PREFIX}/share/gnuconfig/config.sub" source/config.sub
cd source
# Rattler-build may export a nonexistent host-prefix interpreter. With the
# test-data patch, ordinary discovery is harmless and no Python is invoked.
unset PYTHON
# This configuration uses the release production data, with tests disabled;
# skip-disabled-test-data.patch prevents a Python-only test-data dependency.
# The recipe test runtime probe covers selected APIs, not the ICU suite.
./configure --prefix="${PREFIX}" --includedir="${PREFIX}/lib/devkit/include/icu-${LIBRARY_VERSION}" --disable-samples --disable-extras \
  --disable-tests
make -j"${CPU_COUNT}"
make install \
  pkglibdir="${PREFIX}/lib/devkit/lib/icu/${LIBRARY_VERSION}"
# Post-link exception: ICU has no per-tool relative installed RUNPATH setting.
# Build-time tools use upstream loader wrappers; installed tools must load
# channel dependencies without those wrappers.
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
libraries = [path for stem in ['icudata', 'icui18n', 'icuio', 'icutest', 'icutu', 'icuuc'] for path in (prefix / "lib").glob("lib" + stem + ".*")]
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
for name in ['icu-i18n', 'icu-io', 'icu-uc']:
    path = prefix / "lib/pkgconfig" / (name + ".pc")
    target = dev / "lib/pkgconfig" / path.name
    target.parent.mkdir(parents=True, exist_ok=True)
    if path.is_file():
        assert not target.exists(), target
        shutil.move(str(path), target)
    assert target.is_file(), target
    text = target.read_text()
    values = {"prefix": "${pcfiledir}/../..", "exec_prefix": "${prefix}",
              "libdir": "${prefix}/lib", "includedir": "${prefix}/include/icu-78.3"}
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
config = dev / "lib/icu/78.3"
path = config / "Makefile.inc"
text = path.read_text()
values = {'exec_prefix':'$(prefix)', 'libdir':'$(prefix)/lib/devkit/lib',
          'includedir':'$(prefix)/lib/devkit/include/icu-78.3',
          'pkglibdir':'$(prefix)/lib/devkit/lib/$(PACKAGE)$(ICULIBSUFFIX)/$(VERSION)',
          'AR':'llvm-ar', 'CC':'clang', 'CPP':'clang -E', 'CXX':'clang++', 'RANLIB':'llvm-ranlib'}
for key, value in values.items():
    text, count = re.subn(r'(?m)^' + key + r' = .*$', key + ' = ' + value, text)
    assert count == 1, (path, key, count)
text = text.replace('$(LD_RPATH_PRE)$(libdir)', '$(LD_RPATH_PRE)$(prefix)/lib')
text = text.replace('-I$(prefix)/include', '-I$(prefix)/lib/devkit/include/icu-78.3')
path.write_text(text)
path = config / "pkgdata.inc"
text = path.read_text()
values = {'COMPILE':'clang -O2 -c', 'GENLIB':'clang -shared -Wl,-Bsymbolic',
          'LIBFLAGS':'-I' + str(dev / 'include/icu-78.3') + ' -DPIC -fPIC',
          'AR':'llvm-ar', 'RANLIB':'llvm-ranlib', 'INSTALL_CMD':'install -c'}
for key, value in values.items():
    text, count = re.subn(r'(?m)^' + key + r'=.*$', key + '=' + value, text)
    assert count == 1, (path, key, count)
path.write_text(text)
PYCODE
