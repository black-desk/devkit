# Unresolved recipe review findings

These findings came from the 2026-10-17 static review. They remain questions for
investigation, not approved behavior changes or evidence of a fresh build.
Resolved layout migrations, per-package inventories and successful CI histories
are omitted. Recheck the current recipe before implementing a proposed fix.

Feature gaps and their comparison evidence live beside the affected recipes:
[Git](../recipes/git/README.md), [B4](../recipes/b4/README.md),
[Lazygit](../recipes/lazygit/README.md) and [Go](../recipes/go/README.md). The
unresolved ICU environment experiment is recorded
[with ICU](../recipes/icu/README.md#unresolved-merged-environment-experiment).

## Stage test gating

JsonCpp sets `JSONCPP_WITH_POST_BUILD_UNITTEST=ON`; consequently its build can
run unit tests even with `DEVKIT_RUN_TESTS=0`. The shell condition only controls
the later CTest invocation. Installed consumer probes have already moved out of
build scripts; JsonCpp's upstream post-build test remains unchanged. Decide how
to preserve its coverage while honoring the intended stage test schedule.
Compiling a test executable without running it is not itself a test-policy
violation.

## Loader environment resets

Many installed tests still unset `LD_LIBRARY_PATH`/`LD_PRELOAD`, and ICU/libxml2
do so during the build too. These are existing commands, not inherited test
configuration from `build.sh`. Consider removing redundant resets consistently
across recipes. Keep unrelated variables such as `ICU_DATA` and the intentional
Rust toolchain preload as separate decisions. The latter has a concrete
upstream-binary runtime requirement.

## Cleanup ownership

Gettext and libnghttp2 recursively delete every `.la` file below `PREFIX`, which
can also include installed dependency files. Check whether to restrict cleanup
to newly installed output files; do not assume input environments contain no
Libtool archives just because today's packages often omit them.

## Parallelism limits

Gopls uses `go build -p 2`; just and yazi default `CARGO_BUILD_JOBS` to two.
LLVM separately limits simultaneous link jobs to two while allowing compilation
to use `CPU_COUNT`. Review these independently: removing a compilation limit can
change peak memory, and LLVM's link pool is not a limit on all compilation. No
concurrency setting is changed by this review.

## Historical CMake bootstrap patch

Decide whether to remove the unused patch or support its alternate bootstrap
path; the current behavior and rationale are recorded
[beside the CMake recipe](../recipes/cmake/README.md#historical-bootstrap-patch).

## Config-helper override consistency

The installed libxml2 helper has hidden, relocatable default paths, but its
existing `--prefix=...` branch still assigns `libdir=$prefix/lib`. Review
subsequent `--libs` output under that override before changing behavior. PCRE2's
config helper also has prefix/exec-prefix overrides: tests currently check the
reported prefixes, but do not check all subsequent header/library outputs after
an override. This is distinct from the already accepted default layout and needs
focused consumer expectations.
