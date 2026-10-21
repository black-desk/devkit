# Neovim

`recipes/neovim` produces `neovim` 0.12.6 for Linux x86_64, with the executable
`nvim`. After publication, install with the channel selected by the client, for
example `pixi add --channel https://prefix.dev/black-desk neovim`. All new
recipes are ordinary packages discovered by the rendered dependency graph; they
add no seed packages or bootstrap members.

## Independent dependencies

Neovim downloads only its own release source. Its libraries and parsers have
separate recipes, source checksums, package ownership and tests. Channel Clang
23.1.3 and the glibc 2.28 sysroot build the native packages. Library headers and
metadata use the existing version-isolated `lib/devkit` layout.

| Recipe/package         | Version        | Neovim use                                                |
| ---------------------- | -------------- | --------------------------------------------------------- |
| `luajit`               | 2.1.1774638290 | Build interpreter, shared Lua 5.1 library and JIT modules |
| `lua-lpeg`             | 1.1.0          | Shared parsing expression grammar library and Lua module  |
| `luv`                  | 1.52.1         | Shared libuv bindings and Lua module                      |
| `lua-compat-5.3`       | 0.13           | Header/source compatibility layer used to build luv       |
| `unibilium`            | 2.1.2          | Shared terminfo library                                   |
| `libutf8proc`          | 2.11.3         | Shared Unicode library                                    |
| `libtree-sitter`       | 0.26.13        | Shared incremental parser runtime                         |
| `tree-sitter-c`        | 0.24.1         | C parser module                                           |
| `tree-sitter-lua`      | 0.5.0          | Lua parser module                                         |
| `tree-sitter-vim`      | 0.8.1          | Vim parser module                                         |
| `tree-sitter-vimdoc`   | 4.1.0          | Vimdoc parser module                                      |
| `tree-sitter-query`    | 0.8.0          | Query parser module                                       |
| `tree-sitter-markdown` | 0.5.3          | Markdown and inline Markdown parser modules               |

The pins initially follow Neovim 0.12.6's dependency manifest. LuaJIT's version
uses its upstream `.relver` timestamp; the source commit remains pinned. Each
dependency can now be maintained and rebuilt independently. `lua-compat-5.3` is
a noarch development package, needed only when building luv. It is not a Neovim
runtime dependency. Existing libuv, libiconv, gettext and LLVM runtime recipes
remain the other inputs.

Neovim links the channel shared libraries and declares the parser packages as
runtime dependencies. Parser packages own their modules under
`lib/devkit/lib/nvim/parser`; Neovim does not copy them into its own archive.
The independent LuaJIT package owns the interpreter, shared library, headers and
JIT modules. LPeg and luv also provide Lua-loadable module links for standalone
LuaJIT consumers. These links and ELF RUNPATHs are relative to the installation.

## Features and relocation

The package includes LuaJIT, built-in Lua APIs and LSP client, terminal UI,
translations, runtime files, help tags, man page, and all seven upstream default
Tree-sitter parser modules. Neovim's runtime data lives under
`lib/devkit/share/nvim`. Its source patch makes executable-relative data and
parser discovery follow the channel directories; users can still override `VIM`
and `VIMRUNTIME`. LuaJIT resolves its default module directories relative to its
shared library, supporting relocated standalone and embedded use while retaining
`LUA_PATH` and `LUA_CPATH` overrides. No activation-time loader settings are
required.

The LuaJIT unwind patch belongs to its own recipe. It registers the FDE rather
than the initial CIE with LLVM libunwind, matching LuaJIT's existing Darwin
registration convention and preserving JIT and protected-error behavior.

Install the channel's `pynvim` package alongside `neovim` to enable the Python
remote-plugin provider. It includes an isolated Python environment and exposes
the upstream `pynvim-python` discovery command on PATH; Neovim detects it
without a `g:python3_host_prog` setting. The package tests exercise both
embedded RPC and `:python3` buffer operations. See
[the package notes](channel-tools.md) for its dependency pins and installation
scope.

Node.js, Ruby and Perl remote-plugin providers need their corresponding
interpreter and client packages separately. Clipboard helpers, language servers
and additional parsers are external integrations. Unibilium reads the host
terminfo databases; `TERMINFO` and `TERMINFO_DIRS` can select other databases.
Wasmtime support retains the upstream default of off.

## Feature baseline

Compared against conda-forge's editor recipe
[`nvim` at c375289](https://github.com/conda-forge/nvim-feedstock/tree/c375289764e0a517c3064911e24ca3a8c3396a72/recipe),
also version 0.12.6. The conda-forge `neovim` recipe is a Python client. Both
editor builds retain LuaJIT, translations and all default Tree-sitter parsers;
neither enables Wasmtime. Forge uses OpenResty's LuaJIT fork; this channel uses
Neovim's pinned upstream LuaJIT. Full compatibility with fork-specific behavior
is not established. Our parsers are independently packaged instead of built
inside the editor recipe.

## Validation

Dependency package tests exercise standalone LuaJIT/JIT module discovery, LPeg
matching, a luv event-loop timer, Unicode version reporting, terminfo object
allocation, Tree-sitter parser allocation and grammar entry points. Native
packages run the standard ELF RUNPATH and development-layout audit.

Neovim package tests check installed data discovery, LuaJIT compilation and
protected errors, LPeg, libuv, LSP module loading, all seven parsers, file
editing and help loading. Loader, Lua and Vim overrides are cleared and XDG
directories are isolated. Shared-library checks require channel libraries from
the installed prefix. These focused tests do not replace the complete upstream
test suites or exercise every external provider and clipboard helper.

All 13 dependency recipes and Neovim passed focused builds and package tests
against the previously built channel dependencies. A separate runtime extraction
of 16 packages had no duplicate file ownership and excluded `lua-compat-5.3`. It
passed the relocated Neovim/Lua-module smoke tests, interactive terminal
edit/save/quit and the glibc 2.28 audit (21 ELF files). Rendered graph audit, 19
graph tests, 38 pipeline tests, ShellCheck and formatting checks passed. This
validation does not establish a complete self-hosted bootstrap rebuild or
publication to the remote channel.
