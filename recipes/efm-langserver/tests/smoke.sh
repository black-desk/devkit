#!/usr/bin/env bash
set -euxo pipefail
efm-langserver -v | grep -F "efm-langserver ${PKG_VERSION:-0.0.57}"
printf 'version: 2\nlanguages: {}\n' >config.yaml
printf '#!/bin/sh\necho hello\n' >sample.sh
python3 tests/lsp.py --shutdown-closes --document sample.sh --language sh -- efm-langserver -c "${PWD}/config.yaml"
