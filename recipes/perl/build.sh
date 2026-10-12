#!/usr/bin/env bash
set -euxo pipefail

: "${PERL_VERSION:?rattler-build must provide PERL_VERSION}"
: "${SYSROOT_TRIPLET:?rattler-build must provide SYSROOT_TRIPLET}"

source "${SRC_DIR}/devkit-build/build-env.sh"
# Linux hints otherwise query /usr/bin/gcc and may discover host DB/crypt.
# Set the supported discovery overrides explicitly for both compiler variants.
PERL_LIBRARY_PATH="${PREFIX}/lib ${SYSROOT}/lib64"
COMMON_CFLAGS="${CFLAGS} -I${PREFIX}/include/libxcrypt-4.4.38"

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
  -Dcppstdin="${CC} ${PERL_CFLAGS} -E" \
  -Dcppminus=- \
  -Dcpprun="${CC} ${PERL_CFLAGS} -E" \
  -Dcpplast=- \
  -Dld="${CC}" \
  -Dar="${AR}" \
  -Dranlib="${RANLIB}" \
  -Dccflags="${PERL_CFLAGS}" \
  -Dldflags="${LDFLAGS}" \
  -Dlddlflags="-shared ${LDFLAGS}" \
  -Dcccdlflags="-fPIC" \
  -Dsysroot="${SYSROOT}" \
  -Dlibpth="${PERL_LIBRARY_PATH}" \
  -Dplibpth="${PERL_LIBRARY_PATH}" \
  -Dglibpth="${PERL_LIBRARY_PATH}" \
  -Dloclibpth="${PREFIX}/lib" \
  -Dxlibpth=" " \
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
PATH="${TEST_PATH}" devkit_test make test_harness \
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

# Installed XS metadata describes the final channel toolchain, even when this
# interpreter was bootstrapped with seed Clang and seed GCC development files.
export DEVKIT_FLAGS
python3 - "${config_heavy}" "${config_pm}" <<'PYCODE'
import os
from pathlib import Path
import sys
for filename in sys.argv[1:]:
    path = Path(filename)
    text = path.read_text().replace(
        os.environ["DEVKIT_FLAGS"],
        "--no-default-config --config=" + os.environ["BUILD_PREFIX"] + "/share/devkit/clang.cfg",
    )
    text = text.replace("/bin/clang-23", "/bin/clang")
    text = text.replace("x86_64-conda-linux-gnu/sysroot", "x86_64-pc-linux-gnu/sysroot")
    path.write_text(text)
PYCODE
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
    "cc => '__PERL_BUILD_PREFIX__/bin/clang'",
    "cc => $perl_build_prefix . '/bin/clang'",
)
text = text.replace(
    "libpth => '__PERL_BUILD_PREFIX__/lib "
    "__PERL_BUILD_PREFIX__/x86_64-pc-linux-gnu/sysroot/lib64'",
    "libpth => $perl_build_prefix . '/lib ' . "
    "$perl_build_prefix . '/x86_64-pc-linux-gnu/sysroot/lib64'",
)
path.write_text(text)
PY

# Preserve relocatable DT_RUNPATH; package tests run without loader overrides.
python3 "${SRC_DIR}/devkit-build/finalize-elf.py" "${PREFIX}"
