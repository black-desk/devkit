# Shared-link compiler policy

Libtool's shared-library flag allowlist otherwise drops `--config`,
`--no-default-config` and `--ld-path`, reloading Clang's host defaults at link
time. An affected build linked against host glibc 2.32/2.34 despite compiling
against the channel's 2.28 sysroot. Successful tests on a newer host did not
detect that ABI leak.

`clang-driver-link-policy.patch` retains the explicit policy for shared links.
The corrected build's actual link command retained these flags, and its highest
required GLIBC symbol version dropped to 2.17. Use each bundled Libtool's own
quoting implementation; the first attempted fix called a helper absent from
newer generated scripts. The ELF baseline audit checks the installed result.
