# Unresolved application extras

Comparison baseline:
[conda-forge B4](https://github.com/conda-forge/b4-feedstock/tree/81cdb9a79d1be70d751b6f3d6d18f00a8240ef8f/recipe).
The baseline is older than the pinned application; its dependency list cannot be
copied without checking current upstream requirements.

B4 0.16.0 declares completion (shtab) and tui (textual[syntax], rich) extras.
Our wheel/lock includes the current core dependencies but neither extra. Forge's
older B4 recipe installs textual, generates Bash/Zsh completions and installs
the man page. Do not reintroduce forge's old git-filter-repo dependency without
checking the newer upstream: 0.16 replaces it with pygit2/ezgb/liblore. Optional
GnuPG/git-bug integrations should be distinguished from forge-enabled features;
their helper executables are not declared by the inspected baseline.
