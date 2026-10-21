#!/usr/bin/env bash
set -euxo pipefail
mkdir -p "${PREFIX}/bin" "${PREFIX}/lib/devkit/share/shellcheck"
install -m 0755 shellcheck "${PREFIX}/bin/shellcheck"
install -m 0644 README.txt LICENSE.txt "${PREFIX}/lib/devkit/share/shellcheck/"
