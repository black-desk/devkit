# Mail tools

The ordinary recipes add notmuch 0.39, aerc 0.22.0, lei (public-inbox 2.0.0) and
lieer 1.6. They use the channel toolchain and its private installation layout.
They do not add packages to the bootstrap seed. The rendered dependency graph
orders the new libraries and applications automatically.

| Package | Interface and packaging                                                                                                                                    |
| ------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| notmuch | `notmuch`, the shared C API, and versioned private headers; local full-text indexing, search and tags                                                      |
| aerc    | `aerc`, upstream filters, templates, configuration examples and manuals; explicitly enables the cgo notmuch backend alongside IMAP, JMAP, Maildir and mbox |
| lei     | `lei` from public-inbox, with its pinned CPAN closure in `lib/devkit/lib/perl-tools/lei`; other upstream server commands stay private                      |
| lieer   | `gmi`, with a locked offline uv environment in `lib/devkit/share/devkit/python-tools/lieer`; matching notmuch2 bindings built from the notmuch 0.39 source |

Native dependencies are libffi 3.4.8, GLib 2.84.4, talloc 2.5.0, Xapian 1.4.32,
libgpg-error 1.51, libassuan 3.0.2, GPGME 1.24.2 and GMime 3.2.7. scdoc 1.11.3
builds aerc's manuals. Meson comes from the pinned Pixi orchestration
environment, as specified in `pixi.lock`; it is not a target package or a
conda-forge fallback. Libraries and upstream-generated metadata are installed
directly under `lib/devkit`. Query helpers for Xapian and GnuPG libraries stay
in private libexec directories. The recipe-local ELF finalizer handles upstream
build systems without a distinct relative install RUNPATH.

The GLib directory-option patch puts GDB auto-load scripts beside the shared
libraries, avoiding directory names containing the build prefix. It preserves
upstream defaults. TODO: upstream the Meson option. This patch and the
recipe-local Libtool Clang-policy patches were generated with Python `difflib`
against the pinned releases.

GMime enables its GPGME crypto interface. GPGME invokes an external GnuPG
installation for PGP/S/MIME operations; GnuPG, secret keys, agents and pinentry
are not bundled. Building notmuch also needs the build host's `gpg` and `gpgsm`
for its upstream configure-time crypto checks. aerc can also use its built-in Go
crypto provider. The notmuch configure patch passes caller `LDFLAGS` to all four
GMime runtime probes so they load the host-prefix libraries. It preserves the
crypto checks; TODO: submit upstream. The patch was generated with Python
`difflib` against notmuch 0.39. Optional user filters may need external
programs. No account configuration, credentials, mail store or synchronization
job is installed automatically.

lei's private modules are DBI 1.656, DBD::SQLite 1.78 (with its upstream-bundled
SQLite), Search::Xapian 1.2.25.7, URI 5.40, Email::Address::XS 1.05,
Socket::MsgHdr 0.06 and MIME::Base32 1.303. Test::Needs 0.002010 and
Test::Warnings 0.038 support upstream URI tests in the same private tree;
Devel::Leak 0.03 supports the Search::Xapian tests. CPAN sources and hashes are
explicit recipe inputs; builds do not invoke a network CPAN installer. Native
extensions use the merged build/host Perl environment, retaining its original
compiler configuration. The public launcher adds only the private module tree.
HTTP external searches use the channel curl and Git. Optional IMAP-client and
public-inbox web/server modules are outside this package's promise.

A small public-inbox patch moves loading of its optional just-in-time C++ helper
into the existing fallback boundary. This keeps ordinary lei queries usable
without installing a compiler at runtime; native Search::Xapian remains
available. TODO: submit upstream; patch generated with Python `difflib` against
public-inbox 2.0.0.

lieer's `requirements.lock` constrains both runtime and build dependencies;
`recipe.yaml` contains every artifact URL and SHA-256. Update the constraints
and artifact inventory together. Install setuptools/wheel/CFFI from the locked
local wheel set, then build lieer and notmuch2 wheels before offline
`uv tool install`. Imported manylinux extensions retain their bundled libraries
and RPATHs, following b4's exemption. Only the source-built notmuch2 extension
gets a relative channel RUNPATH, checked independently. Dependency license
notices are collected in package metadata. Gmail OAuth and actual remote
synchronization require the user's account and network access.

The aerc resource-directory patch resolves recipe-selected relative paths from
the installed executable. This avoids embedding a build prefix in Go string
headers, which cannot safely be shortened by ordinary binary prefix
substitution. It preserves upstream absolute-directory behavior. TODO: offer
this relative-directory support upstream; patch generated with Python's
standard-library `difflib` against aerc 0.22.0. A second
upstream-default-preserving patch adds desktop-file and icon install directory
options; their outputs also stay under the private data directory.

aerc 0.22.0 discovers the notmuch database and mail root through libnotmuch. Use
`source = notmuch://` for the default profile, or `notmuch://PROFILE` for a
named profile. Discovery follows `NOTMUCH_CONFIG`, `NOTMUCH_DATABASE`,
`NOTMUCH_PROFILE` and the standard notmuch configuration locations. The older
`maildir-store` option is replaced by `enable-maildir` (default: true). This
supports configurations written for automatic discovery; aerc 0.21.0 instead
required an explicit database path in the source URL.

Package tests compile installed C/C++ consumers for all eight libraries, render
a manual with scdoc, index/search/tag a local message with notmuch, check aerc's
installed resources and notmuch linkage, open a terminal to verify automatic
notmuch discovery and display of a local message, import/query a local message
with lei, and import lieer's Google client dependencies and exercise notmuch2
database creation and tags. These tests use installed prefixes and no live mail
accounts. Broader interactive terminal behavior, OAuth consent and remote
Gmail/IMAP services remain outside offline smoke coverage.
