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
cp "${BUILD_PREFIX}/share/gnuconfig/"config.* .
export PKG_CONFIG="${BUILD_PREFIX}/bin/pkgconf"
export PKG_CONFIG_LIBDIR="${PREFIX}/lib/devkit/lib/pkgconfig"
unset PKG_CONFIG_PATH
export CPPFLAGS="${CPPFLAGS} -I${PREFIX}/lib/devkit/include/krb5-1.22.2"
export LDFLAGS="${LDFLAGS} -Wl,-rpath,${SRC_DIR}/lib/.libs"
# Match the exact seed's native features. HTTP/3, IDN2, Brotli and LDAP
# are absent from its closure; do not discover host backends.
./configure --prefix="${PREFIX}" --libdir="${PREFIX}/lib" \
  --includedir="${PREFIX}/lib/devkit/include/curl-${CURL_VERSION}" \
  --enable-shared --enable-static --enable-websockets --enable-manual \
  --with-openssl --with-zlib --with-zstd --with-libpsl \
  --with-libssh2 --with-nghttp2 --with-gssapi="${PREFIX}" \
  --with-gssapi-includes="${PREFIX}/lib/devkit/include/krb5-1.22.2" \
  --with-ca-bundle="${PREFIX}/etc/ssl/certs/ca-certificates.crt" \
  --without-ca-path --without-ca-fallback \
  --without-ngtcp2 --without-quiche --without-libidn2 --without-libssh \
  --without-brotli --disable-ares --disable-ldap --disable-ldaps
make -j"${CPU_COUNT}"
make install pkgconfigdir="${PREFIX}/lib/devkit/lib/pkgconfig"
rm -rf "${PREFIX}/lib/cmake/CURL"
rm -f "${PREFIX}/lib/libcurl.la" "${PREFIX}/bin/wcurl"
# Post-link exception: Libtool links both library and CLI with build/host paths; it lacks CMake-style separate build and install RUNPATH settings.
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
libraries = [path for stem in ['curl'] for path in (prefix / "lib").glob("lib" + stem + ".*")]
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
for name in ['libcurl']:
    path = prefix / "lib/pkgconfig" / (name + ".pc")
    target = dev / "lib/pkgconfig" / path.name
    target.parent.mkdir(parents=True, exist_ok=True)
    if path.is_file():
        assert not target.exists(), target
        shutil.move(str(path), target)
    assert target.is_file(), target
    text = target.read_text()
    values = {"prefix": "${pcfiledir}/../..", "exec_prefix": "${prefix}",
              "libdir": "${prefix}/lib", "includedir": "${prefix}/include/curl-8.22.0"}
    lines = text.splitlines(keepends=True)
    for key, value in values.items():
        matches = [i for i, line in enumerate(lines) if re.match(r"^" + key + r"\s*=", line)]
        if matches:
            assert len(matches) == 1, (target, key)
            lines[matches[0]] = key + "=" + value + "\n"
        elif key == "prefix":
            lines.insert(0, key + "=" + value + "\n")
    text = "".join(lines)
    text = text.replace('-Wl,-rpath -Wl,' + str(prefix) + '/lib', '-Wl,-rpath -Wl,${prefix}/../../lib')
    # Recorded input prefixes become metadata-relative paths, preserving library order.
    text = text.replace(str(prefix) + "/lib/devkit", "${prefix}")
    text = text.replace(str(prefix) + "/lib", "${libdir}")
    text = text.replace(str(prefix) + "/include", "${includedir}")
    target.write_text(text)
# Keep curl-config's generated dependency list; only relocate its query paths.
source = prefix / "bin/curl-config"
path = prefix / "libexec/curl/bin/curl-config"
path.parent.mkdir(parents=True, exist_ok=True)
shutil.move(str(source), path)
text = path.read_text()
text = re.sub(r"(?m)^prefix=.*$", 'prefix="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"', text, count=1)
text = re.sub(r"(?m)^exec_prefix=.*$", 'exec_prefix="${prefix}"', text, count=1)
text = re.sub(r"(?m)^includedir=.*$", 'includedir="${prefix}/lib/devkit/include/curl-8.22.0"', text, count=1)
# Original curl-config embeds libdir at each query site rather than defining a variable.
text = text.replace('-Wl,-rpath -Wl,' + str(prefix) + '/lib', '-Wl,-rpath -Wl,${prefix}/lib')
text = text.replace(str(prefix) + '/lib/devkit', '${prefix}/lib/devkit')
text = text.replace(str(prefix) + '/lib', '${prefix}/lib/devkit/lib')
text = text.replace(str(prefix), '${prefix}')
# The upstream --ca branch single-quotes the configured literal path.
text = re.sub(r'(--ca\)\s*\n\s*)echo .*', lambda m: m[1] + 'echo "${prefix}/etc/ssl/certs/ca-certificates.crt"', text)
text = re.sub(r'(--cc\)\s*\n\s*)echo .*', lambda m: m[1] + 'echo "${prefix}/bin/clang"', text)
path.write_text(text)
PYCODE
