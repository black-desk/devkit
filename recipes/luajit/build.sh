#!/usr/bin/env bash
set -euxo pipefail

export PATH="${BUILD_PREFIX}/bin:${PATH}"
export CC="${BUILD_PREFIX}/bin/clang"
export AR="${BUILD_PREFIX}/bin/llvm-ar"
export RANLIB="${BUILD_PREFIX}/bin/llvm-ranlib"
export CFLAGS="--no-default-config --config=${BUILD_PREFIX}/lib/devkit/share/devkit/clang.cfg -O2 -fPIC"
export CPPFLAGS=""
export LDFLAGS="-L${PREFIX}/lib/devkit/lib -Wl,-rpath-link,${PREFIX}/lib/devkit/lib"
export PKG_CONFIG="${BUILD_PREFIX}/bin/pkg-config"
export PKG_CONFIG_LIBDIR="${PREFIX}/lib/devkit/lib/pkgconfig"
export PKG_CONFIG_PATH="${PKG_CONFIG_LIBDIR}"

# Use a driver so LuaJIT's Makefile cannot discard the sysroot flags.
cat >"${SRC_DIR}/devkit-cc" <<DRIVER
#!/usr/bin/env bash
exec "${CC}" ${CFLAGS} -D_GNU_SOURCE -DDEVKIT_LLVM_UNWIND "\$@"
DRIVER
chmod +x "${SRC_DIR}/devkit-cc"
args=(CC="${SRC_DIR}/devkit-cc" HOST_CC="${SRC_DIR}/devkit-cc"
	"TARGET_AR=${AR} rcus" PREFIX="${PREFIX}" MULTILIB=lib/devkit/lib
	INSTALL_INC="${PREFIX}/lib/devkit/include/luajit-2.1.1774638290"
	INSTALL_SHARE_="${PREFIX}/lib/devkit/share"
	INSTALL_LJLIBD="${PREFIX}/lib/devkit/share/luajit-2.1"
	BUILDMODE=dynamic TARGET_DYNXLDOPTS=
	"LDFLAGS=${LDFLAGS} -Wl,--enable-new-dtags,-rpath,'\$\$ORIGIN/../lib/devkit/lib:\$\$ORIGIN'")
make -j"${CPU_COUNT}" "${args[@]}"
make install "${args[@]}"
# Advertise the same module installation directories used by the loader.
python3 - <<'PC'
import os
from pathlib import Path
p = Path(os.environ["PREFIX"]) / "lib/devkit/lib/pkgconfig/luajit.pc"
p.write_text(p.read_text().replace("INSTALL_LMOD=${prefix}/share/", "INSTALL_LMOD=${prefix}/lib/devkit/share/"))
PC
