#!/usr/bin/env bash
set -euxo pipefail

# Exercise the upstream fallback without a runtime C++ helper build.
export PI_NO_CXX=1
export HOME="${PWD}/home"
export XDG_CONFIG_HOME="${HOME}/config"
export XDG_DATA_HOME="${HOME}/data"
export XDG_CACHE_HOME="${HOME}/cache"
# Unix socket paths must fit Linux's 108-byte limit even in long build prefixes.
XDG_RUNTIME_DIR="$(mktemp -d /tmp/devkit-lei.XXXXXXXX)"
export XDG_RUNTIME_DIR
trap 'lei daemon-kill || true; rm -rf "${XDG_RUNTIME_DIR}"' EXIT
lei init "${HOME}/store"
cat >message.eml <<EOF
From: sender@example.invalid
To: devkit@example.invalid
Subject: devkit searchable message
Message-ID: <devkit-lei@example.invalid>
Date: Wed, 21 Oct 2026 10:00:00 +0000

Local query test.
EOF
lei import -F eml message.eml
lei q --no-external --no-save -f json s:searchable >result.json
grep -F devkit-lei@example.invalid result.json
lei ls-external >externals.txt
test ! -s externals.txt
