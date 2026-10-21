#!/usr/bin/env bash
set -euxo pipefail

export PATH="${BUILD_PREFIX}/bin:${PATH}"
export CC="${BUILD_PREFIX}/bin/clang"
export CXX="${BUILD_PREFIX}/bin/clang++"
export AR="${BUILD_PREFIX}/bin/llvm-ar"
export RANLIB="${BUILD_PREFIX}/bin/llvm-ranlib"
export NM="${BUILD_PREFIX}/bin/llvm-nm"
export STRIP="${BUILD_PREFIX}/bin/llvm-strip"
export CFLAGS="--no-default-config --config=${BUILD_PREFIX}/lib/devkit/share/devkit/clang.cfg -O2 -fPIC"
export CXXFLAGS="${CFLAGS}"
export CPPFLAGS=""
export LDFLAGS="--no-default-config --config=${BUILD_PREFIX}/lib/devkit/share/devkit/clang.cfg -L${PREFIX}/lib/devkit/lib -Wl,-rpath-link,${PREFIX}/lib/devkit/lib -Wl,--enable-new-dtags,-rpath,${PREFIX}/lib/devkit/lib"
export PKG_CONFIG="${BUILD_PREFIX}/bin/pkg-config"
export PKG_CONFIG_LIBDIR="${PREFIX}/lib/devkit/lib/pkgconfig"
export PKG_CONFIG_PATH="${PKG_CONFIG_LIBDIR}"

export GOPATH="${SRC_DIR}/.go-path"
export GOMODCACHE="${SRC_DIR}/.go-mod-cache"
export GOCACHE="${SRC_DIR}/.go-build-cache"
export GOENV=off GOWORK=off GOTOOLCHAIN=local GOTELEMETRY=off
export CGO_ENABLED=1
export CGO_CFLAGS="${CFLAGS} -I${PREFIX}/lib/devkit/include/notmuch-0.39"
export CGO_LDFLAGS="${LDFLAGS}"
export GOFLAGS="-mod=readonly -tags=notmuch"
go mod download
go mod verify
# Date is the timestamp of the pinned upstream release archive.
make_args=(
  VERSION="${PKG_VERSION}" DATE=2025-08-28
  PREFIX="${PREFIX}" SHAREDIR="${PREFIX}/lib/devkit/share/aerc"
  LIBEXECDIR="${PREFIX}/lib/devkit/libexec/aerc"
  MANDIR="${PREFIX}/lib/devkit/share/man"
  DESKTOPDIR="${PREFIX}/lib/devkit/share/applications"
  GO_EXTRA_LDFLAGS="-X git.sr.ht/~rjarry/aerc/config.shareDir=lib/devkit/share/aerc -X git.sr.ht/~rjarry/aerc/config.libexecDir=lib/devkit/libexec/aerc"
)
make -j"${CPU_COUNT}" "${make_args[@]}"
go test ./...
make install "${make_args[@]}"

# Post-link exception: Go/cgo and filter Make rules use build-time linker flags.
# Normalize newly installed ELF to relative channel RUNPATH.
# TODO: upstream separate build/install RUNPATH support.
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"
