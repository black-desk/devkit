#!/usr/bin/env bash
set -euxo pipefail
unset LD_LIBRARY_PATH
test "$(ninja --version)" = 1.13.2
cat >build.ninja <<'EOF'
rule generate
  command = printf 'devkit\n' > $out
build result: generate
EOF
ninja
test "$(cat result)" = devkit
ninja -n | grep -F 'no work to do'
ldd "${PREFIX}/bin/ninja" | tee linked.txt
for library in libstdc++.so.6 libgcc_s.so.1; do
	resolved="$(awk -v name="$library" '$1 == name {print $3}' linked.txt)"
	test -n "$resolved"
	test "$(realpath "$resolved")" = "$(realpath "${PREFIX}/lib/$library")"
done
