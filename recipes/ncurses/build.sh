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
# TODO: Remove the recipe-local LLD workaround when the version maps match
# every component/configuration. Keep split tinfo and versioned symbols enabled.
# https://github.com/NixOS/nixpkgs/pull/309887
# https://github.com/NixOS/nixpkgs/issues/310727
# https://lists.gnu.org/archive/html/bug-ncurses/2024-05/msg00086.html
export LDFLAGS="${LDFLAGS} -lgcc_s -Wl,--undefined-version"
cp "${BUILD_PREFIX}/share/gnuconfig/config.guess" config.guess
cp "${BUILD_PREFIX}/share/gnuconfig/config.sub" config.sub
for mode in narrow wide; do
  wide_option=--disable-widec
  [[ "$mode" == narrow ]] || wide_option=--enable-widec
  ./configure --prefix="${PREFIX}" --includedir="${PREFIX}/include" \
    --without-debug --without-ada --with-shared \
    --with-pkg-config --with-pkg-config-libdir="${PREFIX}/lib/devkit/lib/pkgconfig" \
    --disable-overwrite --enable-symlinks --enable-termcap --enable-pc-files \
    --with-termlib --with-versioned-syms --disable-mixed-case \
    --enable-relative-terminfo "${wide_option}"
  make -j"${CPU_COUNT}"
  make install
  make distclean
done
# Post-link exception: narrow/wide builds install utilities and libraries with
# shared link flags; retain per-file paths until native install relinking is set.
# TODO: configure upstream target-specific install RUNPATH.
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
libraries = [path for stem in ['form', 'formw', 'menu', 'menuw', 'ncurses', 'ncurses++', 'ncurses++w', 'ncursesw', 'panel', 'panelw', 'tinfo', 'tinfow'] for path in (prefix / "lib").glob("lib" + stem + ".*")]
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
for name in ['form', 'formw', 'menu', 'menuw', 'ncurses++', 'ncurses++w', 'ncurses', 'ncursesw', 'panel', 'panelw', 'tinfo', 'tinfow']:
    path = prefix / "lib/pkgconfig" / (name + ".pc")
    target = dev / "lib/pkgconfig" / path.name
    target.parent.mkdir(parents=True, exist_ok=True)
    if path.is_file():
        assert not target.exists(), target
        shutil.move(str(path), target)
    assert target.is_file(), target
    text = target.read_text()
    values = {"prefix": "${pcfiledir}/../..", "exec_prefix": "${prefix}",
              "libdir": "${prefix}/lib", "includedir": "${prefix}/include/ncurses-6.6"}
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
headers = dev / "include/ncurses-6.6"
headers.mkdir(parents=True, exist_ok=True)
for name in ["ncurses", "ncursesw"]:
    shutil.move(str(prefix / "include" / name), headers / name)
# Preserve generated library dependencies while removing build-only compiler/linker flags.
import shlex
for path in (dev / "lib/pkgconfig").glob("*.pc"):
    if path.stem not in ['form','formw','menu','menuw','ncurses++','ncurses++w','ncurses','ncursesw','panel','panelw','tinfo','tinfow']:
        continue
    text = path.read_text()
    subdir = 'ncursesw' if path.stem.endswith('w') else 'ncurses'
    text = re.sub(r'(?m)^includedir=.*$', 'includedir=${prefix}/include/ncurses-6.6/' + subdir, text)
    lines = text.splitlines(keepends=True)
    for i, line in enumerate(lines):
        if line.startswith(('Libs:', 'Libs.private:', 'Cflags:')):
            key, value = line.split(':', 1)
            flags = shlex.split(value)
            allowed = [flag for flag in flags if flag.startswith(('-l', '-L', '-I', '-D', '-U')) or flag == '-pthread']
            lines[i] = key + ': ' + ' '.join(allowed) + '\n'
    path.write_text(''.join(lines))
for name in ['ncurses6-config', 'ncursesw6-config']:
    path = prefix / 'bin' / name
    text = path.read_text()
    text = re.sub(r'(?m)^prefix=.*$', 'prefix="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"', text, count=1)
    text = re.sub(r'(?m)^exec_prefix=.*$', 'exec_prefix="${prefix}"', text, count=1)
    text = text.replace(str(prefix) + '/include', '${prefix}/lib/devkit/include/ncurses-6.6')
    text = text.replace(str(prefix) + '/lib', '${prefix}/lib/devkit/lib')
    text = re.sub(r'(?m)^RPATH_LIST=.*$', 'RPATH_LIST="${prefix}/lib"', text)
    for key in ['CFLAGS', 'LIBS']:
        def clean(match):
            flags = shlex.split(match[1])
            allowed = [flag for flag in flags if flag.startswith(('-l','-L','-I','-D','-U')) or flag == '-pthread']
            return key + '="' + ' '.join(allowed) + '"'
        text = re.sub(r'(?m)^' + key + r'="(.*)"$', clean, text)
    text = re.sub(r'(?m)^for opt in -L\$libdir .*\$LIBS$', 'for opt in -L$libdir $LIBS', text)
    path.write_text(text)
PYCODE
