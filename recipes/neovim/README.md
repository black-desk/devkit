# LuaJIT source choice

The editor uses the LuaJIT revision selected by its own upstream dependency
manifest, while the inspected
[conda-forge editor recipe](https://github.com/conda-forge/nvim-feedstock/tree/c375289764e0a517c3064911e24ca3a8c3396a72/recipe)
uses OpenResty's fork. Following the editor's pinned source keeps its dependency
choice explicit; compatibility with fork-specific behavior remains unverified.
The conda-forge `neovim` feedstock names its Python client; the editor
comparison must use the `nvim` feedstock.
