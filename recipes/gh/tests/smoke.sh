#!/usr/bin/env bash
set -euxo pipefail

export GH_CONFIG_DIR="${PWD}/gh-config"
export GH_PROMPT_DISABLED=1 GH_NO_UPDATE_NOTIFIER=1
export GH_PAGER=cat
unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN

test "$(command -v gh)" = "${PREFIX}/bin/gh"
test "$(command -v git)" = "${PREFIX}/bin/git"
gh config set git_protocol ssh --host example.invalid
test "$(gh config get git_protocol --host example.invalid)" = ssh
gh alias set devkit 'repo view --json name'
gh alias list | grep -F 'repo view --json name'
gh alias set --shell devkit-local 'printf devkit-gh'
test "$(gh devkit-local)" = devkit-gh
gh pr create --help | grep -F -- '--base'

for file in \
	lib/devkit/share/bash-completion/completions/gh \
	lib/devkit/share/fish/vendor_completions.d/gh.fish \
	lib/devkit/share/zsh/site-functions/_gh \
	lib/devkit/share/man/man1/gh.1 \
	lib/devkit/share/man/man1/gh-pr-create.1; do
	test -s "${PREFIX}/${file}"
done
