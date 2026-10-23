# Unresolved cgo behavior

The inspected
[conda-forge recipe](https://github.com/conda-forge/lazygit-feedstock/tree/92f94af67e3acd85c10812f19d76597209c57391/recipe)
uses its ordinary Go compiler, while this recipe forces `CGO_ENABLED=0`. DNS/NSS
behavior may differ; no removed CLI feature was demonstrated by the static
comparison. Compare native name resolution before deciding whether the pure-Go
setting is acceptable. Restoring cgo would need explicit channel Clang, sysroot
and linker inputs rather than host GCC discovery. This investigation has not
established behavioral equivalence.
