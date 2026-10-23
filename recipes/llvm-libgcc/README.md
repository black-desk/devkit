# Runtime identity and bootstrap constraints

The channel needs a single LLVM unwinder that also satisfies glibc's hardcoded
`dlopen("libgcc_s.so.1")`. Upstream llvm-libgcc originally emitted an ELF with
SONAME `libunwind.so.1` and libgcc filename aliases. A RUNPATH-only probe loaded
that object by path, then glibc `backtrace` loaded host libgcc as well: the
alias did not register libgcc's identity. Executable RUNPATH does not control
glibc's indirect lookup.

`libgcc-soname.patch` makes `libgcc_s.so.1` the canonical identity and keeps the
libunwind names as aliases to the same object. This avoids a second unwinder
without replacing RUNPATH globally with old RPATH or requiring loader variables.
Related upstream context:
[LLVM #192891](https://github.com/llvm/llvm-project/issues/192891),
[the llvm-libgcc refactor](https://github.com/llvm/llvm-project/pull/65455), and
[LLVM's motivation](https://github.com/llvm/llvm-project/blob/main/llvm-libgcc/docs/LLVMLibgcc.md#motivation).
These references do not establish upstream endorsement of this private-prefix
patch.

The generated GCC symbol-version script repeats version nodes. GNU ld.bfd
rejected them as duplicate tags in the initial link; an independent LLD probe
accepted the same script and exported the expected versioned symbol. This is why
the runtime build explicitly selects LLD rather than the host linker.

## GNU seed coexistence

Private installation keeps LLVM-libgcc from colliding with the seed's public GNU
libgcc. Seed tools retain GNU's runtime; rebuilt tools select LLVM's through
RUNPATH. Do not restore the former dirty metadata-only libgcc substitution or
place a public LLVM libgcc alias over the seed library. Equal SONAMEs can still
make a process reuse whichever implementation was loaded first, so directory
separation does not prove mixed-process ABI compatibility.

## Unresolved GNU ABI coverage

The earlier seed-libstdc++ link experiment found six required `GCC_4.3.0`
versions exported only as unversioned symbols by LLVM-libgcc: `__trunctfxf2`,
`__getf2`, `__eqtf2`, `__extendxftf2`, `__unordtf2` and `__letf2`. The installed
runtime probe is retained in
[`check-seed-llvm-runtime.sh`](../../scripts/check-seed-llvm-runtime.sh).

A diagnostic linked against GNU libgcc separately, then ran with the LLVM
implementation through embedded RUNPATH. It passed throw/catch and destructor
checks, nested and asynchronous exceptions, DSO propagation, pthread
cancellation and long-double conversions with one loaded unwinder. Relaxing
LLD's shared-library undefined-symbol check also let the mixed probe link and
run. Neither experiment adds the missing versions or proves full GNU ABI
coverage; that relaxation is not the current coexistence design. Controlled
channel consumers and runtime tests must establish the interfaces they require.

The same research found host nodes `GCC_4.7.0`, `GCC_12.0.0`, `GCC_13.0.0` and
`GCC_14.0.0` absent from the LLVM implementation. Do not infer universal
host-libgcc replacement from successful channel tests. Broader mixed-process
compatibility remains unverified.
