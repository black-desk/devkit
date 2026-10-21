#!/usr/bin/env bash
set -euxo pipefail
printf "probe(1)\n\n# DESCRIPTION\nHello\n" | scdoc >probe.1
grep -F Hello probe.1
