#!/usr/bin/env bash
set -euxo pipefail
unset LD_LIBRARY_PATH
export PKG_CONFIG_LIBDIR="${PREFIX}/lib/pkgconfig:${PREFIX}/share/pkgconfig"
export PKG_CONFIG_PATH="${PKG_CONFIG_LIBDIR}"
test "$(command -v pkg-config)" = "${PREFIX}/bin/pkg-config"
cflags="$(pkg-config --cflags gio-2.0 gobject-2.0)"
libs="$(pkg-config --libs gio-2.0 gobject-2.0)"
[[ " $cflags " != *" -I${PREFIX}/include "* ]]
[[ " $libs " != *" -L${PREFIX}/lib "* ]]
gcc $cflags tests/consumer.c $libs -Wl,-rpath,"${PREFIX}/lib" -o consumer
./consumer
gdbus-codegen --help
glib-mkenums --version
glib-compile-resources --version
ldd ./consumer | tee linked.txt
for library in libglib-2.0.so.0 libgobject-2.0.so.0 libgio-2.0.so.0 libffi.so.8 libpcre2-8.so.0 libz.so.1; do
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
test -f "${PREFIX}/include/glib-2.90.0/glib-2.0/glib.h"
for module in glib-2.0 gobject-2.0 gio-2.0 gio-unix-2.0 gmodule-2.0 gmodule-export-2.0 gmodule-no-export-2.0 gthread-2.0 girepository-2.0; do
	check_flags $(pkg-config --cflags "$module")
	check_flags $(pkg-config --libs "$module")
	check_flags $(pkg-config --libs --static "$module")
done
