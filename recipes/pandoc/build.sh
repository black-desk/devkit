#!/usr/bin/env bash
set -euxo pipefail
mkdir -p "${PREFIX}/bin" "${PREFIX}/lib/devkit/share/man/man1"
install -m 0755 bin/pandoc "${PREFIX}/bin/pandoc"
cp -a share/man/man1/. "${PREFIX}/lib/devkit/share/man/man1/"
# The upstream executable also provides these modes based on argv[0].
ln -s pandoc "${PREFIX}/bin/pandoc-server"
ln -s pandoc "${PREFIX}/bin/pandoc-lua"
