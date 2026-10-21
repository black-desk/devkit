"""Adapt upstream LuaLS/luamake to the channel Clang and libc++ toolchain."""

import os
from pathlib import Path

p = Path("3rd/luamake/compile/ninja/linux.ninja")
s = p.read_text().replace("cc = gcc", "cc = $DEVKIT_LUA_CC $DEVKIT_LUA_FLAGS")
s = s.replace("ar = ar", "ar = llvm-ar")
s = s.replace("-static-libgcc", "").replace("-lstdc++fs", "")
s = s.replace("-Wl,-Bstatic -lstdc++ -Wl,-Bdynamic", "").replace("-lstdc++", "")
# Ninja variables are explicit; the compiler config selects libc++ and sysroot.
s = s.replace(
    "$cc $in -o $out",
    "$cc $in -o $out -lc++ -Wl,-rpath,"
    + os.environ["BUILD_PREFIX"]
    + "/lib/devkit/lib",
)
s = (
    "DEVKIT_LUA_CC = "
    + os.environ["DEVKIT_LUA_CC"]
    + "\nDEVKIT_LUA_FLAGS = "
    + os.environ["DEVKIT_LUA_FLAGS"]
    + "\n"
    + s
)
p.write_text(s)
p = Path("3rd/luamake/scripts/compiler/clang.lua")
s = p.read_text().replace('"-lstdc++"', '"-lc++"')
p.write_text(s)
for p in [
    Path("3rd/bee.lua/compile/common.lua"),
    Path("3rd/luamake/bee.lua/compile/common.lua"),
]:
    p.write_text(p.read_text().replace("stdc++fs", "c++"))
# libc++ does not provide libstdc++'s incidental <algorithm> include.
p = Path(
    "3rd/EmmyLuaCodeStyle/CodeFormatCore/src/Diagnostic/Spell/CodeSpellChecker.cpp"
)
p.write_text("#include <algorithm>\n" + p.read_text(encoding="utf-8-sig"))
p = Path("make.lua")
p.write_text(p.read_text().replace('crt = "static"', 'crt = "dynamic"'))
