#!/usr/bin/env bash
# Local integration check: this intentionally requires host GCC development
# files, as does the installed compiler's default host compilation policy.
set -euo pipefail
unset LD_LIBRARY_PATH LD_PRELOAD
PREFIX="$(realpath "${1:?usage: check-clang-policy.sh INSTALL_PREFIX}")"
PROBE_DIR="$(mktemp -d)"
trap 'rm -rf -- "${PROBE_DIR}"' EXIT

cat > "${PROBE_DIR}/probe.cpp" <<'CPP'
#include <algorithm>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>
int main() {
  std::vector<int> values{3, 1, 2};
  std::sort(values.begin(), values.end());
  try { throw std::runtime_error("host"); }
  catch (const std::exception& e) {
    std::cout << e.what() << ':' << values.front() << '\n';
  }
}
CPP

env -u LD_LIBRARY_PATH -u CPATH -u CPLUS_INCLUDE_PATH -u LIBRARY_PATH \
  "${PREFIX}/bin/clang++" -std=c++20 -v "${PROBE_DIR}/probe.cpp" \
  -o "${PROBE_DIR}/probe" > "${PROBE_DIR}/compile.log" 2>&1
cat "${PROBE_DIR}/compile.log"
grep -F 'Selected GCC installation: /usr/' "${PROBE_DIR}/compile.log"
grep -F '"/usr/bin/ld"' "${PROBE_DIR}/compile.log"
if grep -F "${PREFIX}/include" "${PROBE_DIR}/compile.log"; then
  echo 'error: default compilation found channel headers' >&2
  exit 1
fi
dependencies="$(env -u LD_LIBRARY_PATH ldd "${PROBE_DIR}/probe")"
printf '%s\n' "${dependencies}"
grep -F 'libstdc++.so.6 =>' <<< "${dependencies}"
if grep -F "${PREFIX}/" <<< "${dependencies}"; then
  echo 'error: default output loads channel libraries' >&2
  exit 1
fi
test "$(env -u LD_LIBRARY_PATH "${PROBE_DIR}/probe")" = host:1

# The compiler process itself must use the packaged C++ implementation.
compiler_dependencies="$(env -u LD_LIBRARY_PATH ldd "${PREFIX}/bin/clang")"
printf '%s\n' "${compiler_dependencies}"
grep -F 'libc++.so.1 =>' <<< "${compiler_dependencies}" | grep -F "${PREFIX}/"
if grep -F 'libstdc++.so.6 =>' <<< "${compiler_dependencies}"; then
  echo 'error: compiler process depends on GNU libstdc++' >&2
  exit 1
fi
