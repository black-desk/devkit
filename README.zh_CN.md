<!--
SPDX-FileCopyrightText: 2025 Chen Linxuan <me@black-desk.cn>

SPDX-License-Identifier: MIT
-->

# DevKit

[![checks][badge-shields-io-checks]][actions]

[badge-shields-io-checks]:
  https://img.shields.io/github/check-runs/black-desk/devkit/master

[actions]: https://github.com/black-desk/devkit/actions

[en](README.md) | zh_CN

我的个人 conda recipe 仓库。这里存放的是我提交到 conda-forge 但 PR
尚未合并的包、我自己打过 patch 的包或者其他类似的东西。

构建产物会发布到我的 [prefix.dev channel](https://prefix.dev/channels/black-desk)。

## 使用方法

添加 channel：

```bash
# conda
conda config --add channels https://prefix.dev/black-desk

# mamba / micromamba
mamba config prepend channels https://prefix.dev/black-desk
```

或者直接安装指定包：

```bash
conda install --channel https://prefix.dev/black-desk <package-name>

mamba install --channel https://prefix.dev/black-desk <package-name>
```

## 支持平台

- `linux-64`
- `osx-arm64`

## 许可证

如无特殊说明，该项目的代码以 GNU 通用公共许可协议第三版或任何更新的版本开源，文档、配置文件以及开发维护过程中使用的脚本等以 MIT 许可证开源。

该项目遵守 [REUSE 规范]。

你可以使用 [reuse-tool](https://github.com/fsfe/reuse-tool) 生成这个项目的 SPDX 列表：

```bash
reuse spdx
```

[REUSE 规范]: https://reuse.software/spec-3.3/
