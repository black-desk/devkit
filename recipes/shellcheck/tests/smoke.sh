#!/usr/bin/env bash
set -euxo pipefail
shellcheck --version | grep -F 'version: 0.11.0'
# shellcheck disable=SC2016
printf '#!/bin/sh\necho "$HOME"\n' >good.sh
shellcheck good.sh
# shellcheck disable=SC2016
printf '#!/bin/sh\necho $HOME\n' >bad.sh
if shellcheck --format=json bad.sh >diagnostics.json; then
	echo 'expected an unquoted-variable diagnostic' >&2
	exit 1
fi
python3 -c 'import json; assert any(d["code"] == 2086 for d in json.load(open("diagnostics.json")))'
