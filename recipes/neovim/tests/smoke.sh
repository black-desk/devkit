#!/usr/bin/env bash
set -euxo pipefail

unset LD_LIBRARY_PATH LD_PRELOAD VIM VIMRUNTIME LUA_PATH LUA_CPATH
export XDG_CONFIG_HOME="${PWD}/config"
export XDG_DATA_HOME="${PWD}/data"
export XDG_STATE_HOME="${PWD}/state"
export XDG_CACHE_HOME="${PWD}/cache"
test "$(command -v nvim)" = "${PREFIX}/bin/nvim"
nvim --version | grep -F 'NVIM v0.12.6'
nvim --headless -u NONE -i NONE -n -l tests/runtime.lua 2>runtime.log
cat runtime.log
if grep -F 'bad fde' runtime.log; then
	exit 1
fi
printf 'devkit-neovim\n' >expected.txt
cmp expected.txt edited.txt
libraries="$(ldd "${PREFIX}/bin/nvim")"
for soname in libuv.so.1 libiconv.so libunibilium.so.4 \
	libluajit-5.1.so.2 liblpeg.so.1 libluv.so.1 libutf8proc.so.3 libtree-sitter.so.0.26; do
	echo "${libraries}" | grep -F "${soname}" | grep -F "${PREFIX}/bin/../lib/devkit/lib/"
done
! echo "${libraries}" | grep -F 'not found'
