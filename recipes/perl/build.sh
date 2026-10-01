#!/usr/bin/env bash
set -euxo pipefail

: "${PERL_VERSION:?rattler-build must provide PERL_VERSION}"
: "${SYSROOT_TRIPLET:?rattler-build must provide SYSROOT_TRIPLET}"

test -x "${BUILD_PREFIX}/bin/gcc"
test -x "${BUILD_PREFIX}/bin/ar"
test -x "${BUILD_PREFIX}/bin/ld"
test -x "${BUILD_PREFIX}/bin/make"

SYSROOT="${BUILD_PREFIX}/${SYSROOT_TRIPLET}/sysroot"
test -d "${SYSROOT}"

export PATH="${BUILD_PREFIX}/bin:${PATH}"
CC="${BUILD_PREFIX}/bin/gcc"
COMMON_CFLAGS="--sysroot=${SYSROOT} -O2 -pipe"
PERL_CFLAGS="${COMMON_CFLAGS} -D_REENTRANT -D_GNU_SOURCE -fwrapv -fno-strict-aliasing -fstack-protector-strong -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64"

./Configure \
  -de \
  -Dprefix="${PREFIX}" \
  -Duserelocatableinc \
  -Dinstallstyle=lib/perl5 \
  -Dinstallusrbinperl=n \
  -Dusethreads \
  -Dinc_version_list=none \
  -Dcc="${CC}" \
  -Dld="${CC}" \
  -Dar="${BUILD_PREFIX}/bin/ar" \
  -Dranlib="${BUILD_PREFIX}/bin/ranlib" \
  -Dccflags="${PERL_CFLAGS}" \
  -Dldflags="${COMMON_CFLAGS}" \
  -Dlddlflags="-shared ${COMMON_CFLAGS}" \
  -Dcccdlflags="-fPIC" \
  -Dsysroot="${SYSROOT}" \
  -Dmalloctype='void *' \
  -Dfreetype=void \
  -Dmyhostname=devkit \
  -Dmydomain=.invalid \
  -Dperladmin=devkit@invalid \
  -Dcf_by=black-desk \
  -Dcf_email=devkit@invalid \
  -Dman1dir=none \
  -Dman3dir=none

make -j"${CPU_COUNT}"

# GNU env 9.12 quotes values containing shell metacharacters, while Perl's
# environment tests expect the traditional raw format. Prefer the runner's
# /usr/bin/env for the selected tests while retaining channel compiler tools.
TEST_PATH="${BUILD_PREFIX}/bin:/usr/bin:/bin"
PATH="${TEST_PATH}" make test_harness \
  HARNESS_OPTIONS="j${CPU_COUNT}" \
  TEST_ARGS='op/magic.t op/tie.t ../lib/perl5db.t'

make install -j"${CPU_COUNT}"

# Perl's build metadata records the compiler and sysroot used during this
# package build. Replace that absolute build-tool prefix with a runtime marker;
# Config_heavy.pl resolves the marker relative to the active perl executable.
config_heavy="${PREFIX}/lib/perl5/${PERL_VERSION}/x86_64-linux-thread-multi/Config_heavy.pl"
config_pm="${PREFIX}/lib/perl5/${PERL_VERSION}/x86_64-linux-thread-multi/Config.pm"
test -n "${config_heavy}"
test -n "${config_pm}"
test -f "${config_heavy}"
test -f "${config_pm}"

chmod u+w "${config_heavy}" "${config_pm}"
sed -i "s|${BUILD_PREFIX}|__PERL_BUILD_PREFIX__|g" "${config_heavy}" "${config_pm}"

python3 - "${config_heavy}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
needle = "my $summary_expanded;\n"
insert = """my $summary_expanded;

use Cwd qw(abs_path);
use File::Basename;
my $perl_build_prefix = dirname(dirname(abs_path($^X)));
"""
if needle not in text:
    raise SystemExit("Config_heavy.pl insertion point not found")
text = text.replace(needle, insert, 1)
needle = "my $i = ord(8);\n"
insert = """$_ =~ s/__PERL_BUILD_PREFIX__/$perl_build_prefix/g;
my $i = ord(8);
"""
if needle not in text:
    raise SystemExit("Config_heavy.pl replacement point not found")
text = text.replace(needle, insert, 1)
path.write_text(text)
PY

python3 - "${config_pm}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
needle = "sub FETCH {\n"
insert = """use Cwd qw(abs_path);
use File::Basename;
my $perl_build_prefix = dirname(dirname(abs_path($^X)));

sub FETCH {
"""
if needle not in text:
    raise SystemExit("Config.pm insertion point not found")
text = text.replace(needle, insert, 1)
text = text.replace(
    "cc => '__PERL_BUILD_PREFIX__/bin/gcc'",
    "cc => $perl_build_prefix . '/bin/gcc'",
)
text = text.replace(
    "libpth => '__PERL_BUILD_PREFIX__/lib "
    "__PERL_BUILD_PREFIX__/x86_64-pc-linux-gnu/sysroot/lib64'",
    "libpth => $perl_build_prefix . '/lib ' . "
    "$perl_build_prefix . '/x86_64-pc-linux-gnu/sysroot/lib64'",
)
path.write_text(text)
PY
