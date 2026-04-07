<!--
SPDX-FileCopyrightText: 2025 Chen Linxuan <me@black-desk.cn>

SPDX-License-Identifier: MIT
-->

# DevKit

[![checks][badge-shields-io-checks]][actions]

[badge-shields-io-checks]:
  https://img.shields.io/github/check-runs/black-desk/devkit/master

[actions]: https://github.com/black-desk/devkit/actions

en | [zh_CN](README.zh_CN.md)

> [!WARNING]
>
> This English README is translated from the Chinese version using LLM and may
> contain errors.

My personal conda recipe repository. These are packages that have pending
conda-forge PRs, have been patched for my own use, or similar things.

Built packages are published to my
[prefix.dev channel](https://prefix.dev/channels/black-desk).

## Usage

Add the channel:

```bash
# conda
conda config --add channels https://prefix.dev/black-desk

# mamba / micromamba
mamba config prepend channels https://prefix.dev/black-desk
```

Or install a package directly:

```bash
conda install --channel https://prefix.dev/black-desk <package-name>

mamba install --channel https://prefix.dev/black-desk <package-name>
```

## Supported Platforms

- `linux-64`
- `osx-arm64`

## License

Unless otherwise specified, the code of this project are open source under the
GNU General Public License version 3 or any later version, while documentation,
configuration files, and scripts used in the development and maintenance process
are open source under the MIT License.

This project complies with the [REUSE specification].

You can use [reuse-tool](https://github.com/fsfe/reuse-tool) to generate the
SPDX list for this project:

```bash
reuse spdx
```

[REUSE specification]: https://reuse.software/spec-3.3/
