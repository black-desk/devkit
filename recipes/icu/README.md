# Release data and consumer configuration

The official release tarball contains production `.dat` data. Upstream selects
it automatically when the text-data tree is absent; see
[ICU #502](https://github.com/unicode-org/icu/pull/502) and
[#503](https://github.com/unicode-org/icu/pull/503). This avoids adding Python,
uv and their build closure merely to regenerate data already supplied by the
release. Source inspection and a byte comparison against the pinned seed's data
confirmed that this mode retained its production data, rather than reducing
locales or converters.

Upstream still tried generating Python test-data rules with tests disabled.
`skip-disabled-test-data.patch` gates that step on the test setting. A sentinel
interpreter experiment confirmed that disabled tests never invoked Python while
enabled tests still generated their rules. Python remains necessary to customize
or regenerate data and run the data-builder tests; the installed API probes do
not replace ICU's full upstream suite.

Build-time `pkgdata.inc` needs the actual build toolchain. Installed consumer
configuration must not retain temporary build-prefix compiler paths and sysroot
flags, so the installation patch generates a separate consumer file through the
same upstream generator. Rewriting the build-time file would break ICU's own
build; exporting it unchanged would leak build-only settings.

## Unresolved merged-environment experiment

Perl and curl can preserve upstream exported compiler settings by merging their
native build/host environments and relying on Conda text-prefix replacement.
Applying that approach to ICU is unresolved. Solving the compiler's dependency
closure brings in libxml2, which itself depends on ICU: an existing ICU can
therefore already be present in the merged prefix.

The recorded solve investigation established that Perl/curl's assumption of no
preinstalled copy does not transfer to ICU. Before attempting a merge, decide
how to stage installation and explicitly collect rebuilt files without losing
ownership or packaging dependency files. No ICU merge was implemented or
validated; the separate consumer generator remains the current design.
