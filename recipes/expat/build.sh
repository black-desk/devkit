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

: "${EXPAT_VERSION:?rattler-build must provide EXPAT_VERSION}"
: "${SYSROOT_TRIPLET:?rattler-build must provide SYSROOT_TRIPLET}"

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

cp "${BUILD_PREFIX}/share/gnuconfig/config.guess" conftools/config.guess
cp "${BUILD_PREFIX}/share/gnuconfig/config.sub" conftools/config.sub

./configure \
  --prefix="${PREFIX}" \
  --libdir="${PREFIX}/lib" \
  --includedir="${PREFIX}/lib/devkit/include/expat-${EXPAT_VERSION}" \
  --enable-shared \
  --enable-static \
  --without-docbook

make -j"${CPU_COUNT}"
if [[ "${DEVKIT_RUN_TESTS:-1}" == 1 ]]; then
  make check
fi
make install pkgconfigdir="${PREFIX}/lib/devkit/lib/pkgconfig" \
  cmakedir="${PREFIX}/lib/devkit/lib/cmake/expat-${EXPAT_VERSION}"

cat >"${SRC_DIR}/devkit-consumer.c" <<'EOF'
#include <expat.h>

#include <stdio.h>
#include <string.h>

static void XMLCALL start(void *userData, const XML_Char *name, const XML_Char **atts) {
  (void)userData;
  (void)atts;
  puts(name);
}

int main(void) {
  XML_Parser parser = XML_ParserCreate(NULL);
  if (parser == NULL) {
    return 1;
  }
  XML_SetElementHandler(parser, start, NULL);
  const char *document = "<devkit/>";
  if (XML_Parse(parser, document, (int)strlen(document), 1) == XML_STATUS_ERROR) {
    XML_ParserFree(parser);
    return 1;
  }
  XML_ParserFree(parser);
  return 0;
}
EOF

"${CC}" \
  ${CFLAGS} ${LDFLAGS} \
  -I"${PREFIX}/lib/devkit/include/expat-${EXPAT_VERSION}" \
  "${SRC_DIR}/devkit-consumer.c" \
  "${PREFIX}/lib/libexpat.so" \
  -Wl,-rpath-link,"${SYSROOT}/lib64" \
  '-Wl,--enable-new-dtags,-rpath,$ORIGIN/runtime-lib' \
  -o "${SRC_DIR}/library-probe"

ln -s "${PREFIX}/lib" runtime-lib

env -u LD_LIBRARY_PATH -u LD_PRELOAD "${SRC_DIR}/library-probe"

# Post-link exception: Autotools/Libtool links xmlwf against its in-tree library; the install interface does not expose a separate relative runtime path.
# TODO: replace with target-specific upstream install/relink support.
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"

# Stage only this package's development interfaces; preserve runtime libraries.
python3 "${SRC_DIR}/devkit-build/stage-development.py" "${PREFIX}" --all
