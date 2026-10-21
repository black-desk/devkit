#!/usr/bin/env bash
set -euxo pipefail

export HOME="${PWD}/home"
export NOTMUCH_CONFIG="${HOME}/notmuch-config"
mkdir -p "${HOME}" mail/{cur,new,tmp}
cat >"${NOTMUCH_CONFIG}" <<EOF
[database]
path=${PWD}/mail
[user]
name=Devkit Test
primary_email=devkit@example.invalid
[new]
tags=inbox;unread;
EOF
cat >mail/new/message <<EOF
From: sender@example.invalid
To: devkit@example.invalid
Subject: devkit searchable message
Message-ID: <devkit-test@example.invalid>
Date: Wed, 21 Oct 2026 10:00:00 +0000

Searchable mail body.
EOF
notmuch --version | grep -F 0.39
notmuch new
test "$(notmuch count subject:searchable)" = 1
notmuch tag +devkit -unread -- id:devkit-test@example.invalid
test "$(notmuch count tag:devkit)" = 1
test "$(notmuch count tag:unread)" = 0
notmuch show --format=json '*' >message.json
grep -F 'Searchable mail body.' message.json
