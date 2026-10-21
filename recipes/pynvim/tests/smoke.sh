#!/usr/bin/env bash
set -euxo pipefail

unset LD_LIBRARY_PATH LD_PRELOAD VIM VIMRUNTIME PYTHONPATH PYTHONHOME
export XDG_CONFIG_HOME="${PWD}/config"
export XDG_DATA_HOME="${PWD}/data"
export XDG_STATE_HOME="${PWD}/state"
export XDG_CACHE_HOME="${PWD}/cache"
export PYTHONNOUSERSITE=1

test "$(command -v pynvim-python)" = "${PREFIX}/bin/pynvim-python"
test "$(readlink "${PREFIX}/bin/pynvim-python")" = ../lib/devkit/share/devkit/python-tools/pynvim/bin/pynvim-python
tool="${PREFIX}/lib/devkit/share/devkit/python-tools/pynvim"
"${tool}/bin/python" -I tests/runtime.py
# The upstream discovery wrapper does not forward Python's exit code, so check
# its output as well as running the substantive tests directly above.
test "$(pynvim-python -I -c 'import pynvim; print(pynvim.__version__)')" = 0.6.0
python -I -c 'import importlib.util; assert importlib.util.find_spec("pynvim") is None'
for extension in "${tool}/lib/python3.14/site-packages/greenlet/"_greenlet*.so; do
	readelf -d "${extension}" | grep -F '(RUNPATH)'
	ldd "${extension}" | grep -F 'libc++.so.1 =>' | grep -F "${PREFIX}/"
	if ldd "${extension}" | grep -F 'libstdc++.so'; then
		exit 1
	fi
done
