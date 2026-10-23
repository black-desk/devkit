# Native environment and exported compiler paths

Perl's Config modules record the compiler and flags needed by later XS builds.
With separate build and host prefixes those paths referred to BUILD_PREFIX,
which host-prefix text relocation did not cover. Merging the native environments
lets upstream install its original Config modules and Conda relocate their
recorded tool paths. A second consumer Config generator is unnecessary.

Dirty builds use the seed-owned versioned compiler names. Creating new driver
aliases in the merged prefix would make them newly installed files and collect
them into Perl's payload. Pure-Perl execution does not require a compiler; XS
users install the matching compiler, Make and sysroot explicitly.

Linux Configure hints otherwise query host GCC and can discover host Berkeley DB
or libcrypt outside the selected sysroot. Supported discovery and preprocessor
overrides keep those probes on the same policy as compilation, preserving crypt
through channel libxcrypt without accidentally enabling host DBM libraries.

Libxcrypt itself uses Perl to generate headers and symbol maps. The previous
bootstrap generation supplies that Perl, breaking the build cycle before the
current generation's Perl is built against channel libxcrypt. Both inputs belong
in the seed; current stage order and exact pins live in the manifests.
