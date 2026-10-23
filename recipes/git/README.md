# Unresolved feature differences

The comparison against
[conda-forge Git 2.56.0](https://github.com/conda-forge/git-feedstock/tree/71aa484678c3d0372e48ad8053b1ce6411f20b80/recipe)
found that `NO_GETTEXT` and `NO_PYTHON` remove translations and Python helpers.
The channel also lacks the baseline's manuals, HTML documentation and Bash
completion. These are open corrections, not approved feature reductions.

Git should restore gettext output translations and Python helpers, ship its Bash
completion, and install the matching upstream man/HTML archives. Forge uses
libiconv as well; check text conversion against the channel implementation when
aligning library selection. Forge sets CSPRNG_METHOD=openssl to support an older
glibc baseline; our getrandom path is compatible with our glibc 2.28 baseline
and does not itself remove a feature. Restoring gitk/git-gui requires a channel
Tcl/Tk interpreter and its GUI dependencies, which are not currently recipes in
this repository. Merely deleting NO_TCLTK would not make those commands usable.
Optional Perl integrations such as git svn also require external modules; the
inspected forge recipe does not declare those either.
