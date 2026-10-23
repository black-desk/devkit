# Channel-specific usage

## Install with micromamba

On Linux x86_64, paste this command to install micromamba and use its `base`
environment as your default Devkit environment:

```bash
bash -e -o pipefail <<'SH'
curl -fsSL https://micro.mamba.pm/install.sh | \
  env BIN_FOLDER="$HOME/.local/bin" PREFIX_LOCATION="$HOME/.local/share/devkit" \
    INIT_YES=yes CONDA_FORGE_YES=no sh
"$HOME/.local/bin/micromamba" config prepend channels https://prefix.dev/black-desk
"$HOME/.local/bin/micromamba" config set auto_activate_base true
"$HOME/.local/bin/micromamba" create -y \
  --root-prefix "$HOME/.local/share/devkit" -n base --override-channels \
  -c https://prefix.dev/black-desk neovim
SH
```

The official installer supports switching conda-forge setup off with
`CONDA_FORGE_YES=no`; it does not accept a custom channel. The following
commands add this channel to the front of your user channel list, preserving any
existing channels. With no previous channel configuration, it is the only
channel. The initial environment resolves exclusively from this channel. Replace
`neovim` with the packages you want to install.

Packages install directly into `base` at `~/.local/share/devkit`. The installer
initializes your shell, and `auto_activate_base` makes new terminals activate
this environment automatically, adding its `bin` directory to PATH. In a new
terminal, type `nvim` to start Neovim; no `micromamba run` prefix is needed.

Run a command without shell activation:

```bash
"$HOME/.local/bin/micromamba" --root-prefix "$HOME/.local/share/devkit" run -n base nvim
```

Add more packages using the saved channel configuration:

```bash
micromamba install -n base ripgrep
```

Recipe presence describes source availability; successful publication determines
what can be installed from the hosted channel.

## Compiler modes

Normal `clang` and `clang++` commands use host development files and the host
linker. C++ compilation therefore requires the host's GCC development headers
and libraries even though the compiler executable uses channel runtimes.

To build against the channel sysroot and LLVM runtimes, opt in explicitly:

```bash
"<prefix>/bin/clang++" --no-default-config \
  --config="<prefix>/lib/devkit/share/devkit/clang.cfg" main.cpp -o main
```

For other channel libraries, set `CMAKE_PREFIX_PATH=<prefix>/lib/devkit` or
`PKG_CONFIG_LIBDIR=<prefix>/lib/devkit/lib/pkgconfig` as appropriate. Use their
metadata for versioned include paths. The compiler config does not set output
RUNPATH; applications using channel shared libraries need a runtime search path
appropriate to their installation location.

## Python environments

Use virtual environments for Python packages. Bundled pip is available through
`python -m pip`. Channel-owned Python tools use private environments; normal
`uv tool list`, upgrade and uninstall operations do not manage them. Do not
point uv at the channel's private tool directories to update packaged files.

Install `pynvim` alongside `neovim` for the Python remote-plugin provider.
Neovim discovers `pynvim-python` on PATH without `g:python3_host_prog`. The
private environment does not add modules to public Python's site-packages;
Python clients can use `pynvim-python -c 'import pynvim'`.

## Typst resource discovery

Environment activation sets package and font paths. Clients without activation
can set `TYPST_PACKAGE_PATH=<prefix>/lib/devkit/share/typst/packages` and
`TYPST_FONT_PATHS=<prefix>/lib/devkit/share/fonts`. Embedded fonts work without
activation; third-party packages and additional fonts must be supplied
separately.

## Mail integration

GPGME-backed PGP/S/MIME operations require an external GnuPG installation,
including any needed agents and pinentry. aerc can also use its Go crypto
provider. Account configuration, credentials, mail stores and synchronization
jobs require user setup.

For aerc's automatic notmuch discovery, use `source = notmuch://` for the
default profile or `notmuch://PROFILE` for a named profile. Discovery follows
`NOTMUCH_CONFIG`, `NOTMUCH_DATABASE`, `NOTMUCH_PROFILE` and standard notmuch
configuration locations. Use `enable-maildir` (default: true) in place of the
older `maildir-store` option.

## Optional integrations

Yazi previews and openers need the corresponding external tools, such as FFmpeg,
Poppler or ImageMagick. Neovim clipboard helpers, language servers and
non-Python remote-plugin providers need separate setup. Unibilium uses host
terminfo; `TERMINFO` and `TERMINFO_DIRS` can select other databases.

Clang-tidy's Python helper needs PyYAML to merge exported diagnostics into one
YAML file. Exporting to a directory and applying replacements do not require it.
