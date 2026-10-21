#!/usr/bin/env bash
set -euxo pipefail

export PATH="${BUILD_PREFIX}/bin:${PATH}"
export DEVKIT_LUA_CC="${BUILD_PREFIX}/bin/clang"
export DEVKIT_LUA_FLAGS="--no-default-config --config=${BUILD_PREFIX}/lib/devkit/share/devkit/clang.cfg"
# Luamake's bootstrap and generated Ninja rules otherwise hardcode GNU runtime
# linkage. Patch only that toolchain integration, retaining all LuaLS features.
python3 "${RECIPE_DIR}/prepare.py"
(
	cd 3rd/luamake
	ninja -f compile/ninja/linux.ninja -j "2" notest
)
# The bootstrap uses the build toolchain runtime; the final ELF uses host libs.
3rd/luamake/luamake -compiler clang -cc "${DEVKIT_LUA_CC} ${DEVKIT_LUA_FLAGS}" \
	-ar "${BUILD_PREFIX}/bin/llvm-ar" \
	-ldflags " ${DEVKIT_LUA_FLAGS} -L${PREFIX}/lib/devkit/lib -Wl,-rpath-link,${PREFIX}/lib/devkit/lib" \
	rebuild -notest -j "2"
install_root="${PREFIX}/lib/devkit/libexec/lua-language-server"
mkdir -p "${install_root}/bin" "${PREFIX}/bin"
install -m 0755 bin/lua-language-server "${install_root}/bin/"
install -m 0644 bin/main.lua "${install_root}/bin/"
install -m 0644 main.lua debugger.lua changelog.md "${install_root}/"
cp -a locale meta script "${install_root}/"
# Relative executable link preserves upstream's executable-relative Lua lookup.
ln -s ../lib/devkit/libexec/lua-language-server/bin/lua-language-server "${PREFIX}/bin/lua-language-server"
# shellcheck disable=SC2016
patchelf --set-rpath '$ORIGIN/../../../lib' "${install_root}/bin/lua-language-server"
