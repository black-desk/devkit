#!/usr/bin/env bash
set -euxo pipefail
unset LD_LIBRARY_PATH
export PKG_CONFIG_LIBDIR="${PREFIX}/lib/pkgconfig:${PREFIX}/share/pkgconfig"
export PKG_CONFIG_PATH="${PKG_CONFIG_LIBDIR}"
test "$(command -v pkg-config)" = "${PREFIX}/bin/pkg-config"
cflags="$(pkg-config --cflags talloc)"
libs="$(pkg-config --libs talloc)"
[[ " $cflags " != *" -I${PREFIX}/include "* ]]
[[ " $libs " != *" -L${PREFIX}/lib "* ]]
gcc $cflags tests/consumer.c $libs -Wl,-rpath,"${PREFIX}/lib" -o consumer
./consumer
ldd ./consumer | tee linked.txt
for library in libtalloc.so.2; do
	resolved="$(awk -v name="$library" '$1 == name {print $3}' linked.txt)"
	test -n "$resolved"
	test "$(realpath "$resolved")" = "$(realpath "${PREFIX}/lib/$library")"
done

# Normalize paths before enforcing the channel's isolated-header and exact-DSO
# policy, including metadata for private/static dependencies.
check_flags() {
	local flag
	for flag in "$@"; do
		case "$flag" in
		-I*) test "$(realpath "${flag#-I}")" != "${PREFIX}/include" ;;
		-L*) test "$(realpath "${flag#-L}")" != "${PREFIX}/lib" ;;
		-lffi | -ltalloc | -lxapian | -lglib-2.0 | -lgobject-2.0 | -lgio-2.0 | -lgmodule-2.0 | -lgthread-2.0 | -lgirepository-2.0 | -lz | -lpcre2-8)
			printf 'error: unqualified channel library: %s\n' "$flag" >&2
			return 1
			;;
		esac
	done
}
test -f "${PREFIX}/include/talloc-2.5.0/talloc.h"
for module in talloc; do
	check_flags $(pkg-config --cflags "$module")
	check_flags $(pkg-config --libs "$module")
	check_flags $(pkg-config --libs --static "$module")
done
