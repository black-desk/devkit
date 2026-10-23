# Package-manager feature selection

The pinned upstream
[Cargo feature definitions](https://github.com/astral-sh/uv/blob/0.12.22/crates/uv/Cargo.toml)
identify `test-defaults` as test-only and reserve `self-update` for the upstream
installer. Omitting self-update leaves upgrades with the channel package
manager. The inspected
[conda-forge recipe](https://github.com/conda-forge/uv-feedstock/tree/1710613e2e6c6ef94f3fd3a1313e7fa5a9e5f5b8/recipe)
also did not enable self-update. Its version differed, so feature claims rely on
the pinned upstream source rather than that newer feedstock alone.

Before adding upstream test execution, determine which test features and
fixtures it requires. A performance-only application build is not evidence that
the upstream test-defaults suite has been exercised.
