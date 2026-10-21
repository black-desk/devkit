#!/usr/bin/env bash
set -euxo pipefail

export XDG_CONFIG_HOME="${PWD}/config"
export XDG_CACHE_HOME="${PWD}/cache"
export XDG_DATA_HOME="${PWD}/data"
mkdir -p destination source "${XDG_CONFIG_HOME}"
touch "${XDG_CONFIG_HOME}/chezmoi.toml"

devkit_chezmoi() {
	chezmoi --no-tty --no-pager \
		--config "${XDG_CONFIG_HOME}/chezmoi.toml" \
		--source "${PWD}/source" --working-tree "${PWD}/source" \
		--destination "${PWD}/destination" "$@"
}

test "$(command -v chezmoi)" = "${PREFIX}/bin/chezmoi"
test "$(command -v git)" = "${PREFIX}/bin/git"
printf 'devkit dotfile\n' >destination/.devkit-probe
devkit_chezmoi add "${PWD}/destination/.devkit-probe"
cmp destination/.devkit-probe source/dot_devkit-probe
rm destination/.devkit-probe
devkit_chezmoi apply --force
cmp destination/.devkit-probe source/dot_devkit-probe
test "$(devkit_chezmoi execute-template '{{ "devkit" | upper }}')" = DEVKIT
test -z "$(devkit_chezmoi status)"

for file in \
	lib/devkit/share/bash-completion/completions/chezmoi \
	lib/devkit/share/fish/vendor_completions.d/chezmoi.fish \
	lib/devkit/share/zsh/site-functions/_chezmoi; do
	test -s "${PREFIX}/${file}"
done
