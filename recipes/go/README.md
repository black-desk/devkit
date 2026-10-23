# Official distribution and unresolved cgo integration

The official Go repack retains upstream's internal toolchain layout rather than
conda-forge's cgo/nocgo variants and conda compiler activation patches.
[The inspected baseline](https://github.com/conda-forge/go-feedstock/tree/9c80ca35f362ced743db27c7cb5260141a93f755/recipe)
also patches flag inheritance, default paths and linker behavior. Those are
integration differences, not evidence that cgo was disabled in the repack.

Downstream cgo builds still need validation with explicit channel Clang and the
sysroot. Any integration must preserve ordinary users' host-build defaults.
Forge's Fortran cgo test coverage does not transfer to this channel, which does
not supply a Fortran compiler. This remains an unverified interface rather than
an implicit promise of feedstock parity.
