"""Check package ownership, real ELF tags, and runtime/development boundaries."""

import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
CHECK = ROOT / "scripts/packaging/check-package.py"
SPEC = importlib.util.spec_from_file_location("package_audit", CHECK)
AUDIT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUDIT)


@unittest.skipUnless(shutil.which("cc") and shutil.which("readelf"), "needs ELF tools")
class PackageAuditTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.prefix = self.root / "prefix"
        self.prefix.mkdir()
        self.source = self.root / "probe.c"
        self.source.write_text("int main(void) { return 0; }\n")

    def elf(self, name="bin/probe", runpath=None, old=False):
        path = self.prefix / name
        path.parent.mkdir(parents=True, exist_ok=True)
        command = ["cc", str(self.source), "-o", str(path)]
        if runpath is not None:
            command.append(f"-Wl,-rpath,{runpath}")
            command.append(
                "-Wl,--disable-new-dtags" if old else "-Wl,--enable-new-dtags"
            )
        subprocess.run(command, check=True)
        return path

    def check(self, package=None, *, skip_runpath=False):
        command = ["python3", str(CHECK), str(self.prefix)]
        if skip_runpath:
            command.append("--skip-runpath-check")
        if package:
            command += ["--package", package]
        return subprocess.run(command, capture_output=True, text=True)

    def record(self, name, files):
        records = self.prefix / "conda-meta"
        records.mkdir(exist_ok=True)
        (records / f"{name}-1-0.json").write_text(
            json.dumps({"name": name, "files": files})
        )

    def test_accepts_origin_runpath_and_no_runpath(self):
        self.elf(runpath="$ORIGIN/../lib")
        self.elf("lib/nested/plugin.so", runpath="${ORIGIN}/..")
        self.elf("bin/libc-only")
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_forbids_rpath_even_when_relative(self):
        self.elf(runpath="$ORIGIN/../lib", old=True)
        result = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("DT_RPATH is forbidden", result.stderr)

    def test_skip_runpath_retains_layout_and_ownership_checks(self):
        self.elf(runpath="/tools/deps/lib", old=True)
        self.record("imported", ["bin/probe"])
        self.assertNotEqual(self.check("imported").returncode, 0)
        result = self.check("imported", skip_runpath=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("ELF RUNPATH: OK", result.stdout)
        self.assertNotEqual(self.check("missing", skip_runpath=True).returncode, 0)
        self.elf("lib/devkit/lib/hidden.so", runpath="/tools/deps/lib", old=True)
        header = self.prefix / "include/probe.h"
        header.parent.mkdir()
        header.write_text("/* public header */")
        self.record(
            "imported", ["bin/probe", "lib/devkit/lib/hidden.so", "include/probe.h"]
        )
        result = self.check("imported", skip_runpath=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("runtime ELF in metadata directory", result.stderr)
        self.assertIn("public development interface", result.stderr)
        self.assertNotIn("DT_RPATH is forbidden", result.stderr)

    def test_rejects_nonrelocatable_and_metadata_runpaths(self):
        for value, message in (
            ("/build/temporary", "non-runtime search path"),
            ("../lib", "non-runtime search path"),
            ("$ORIGIN/../lib:", "non-runtime search path"),
            ("$ORIGIN/../../outside", "escapes prefix"),
            ("$ORIGIN/../lib/devkit/include", "metadata runtime search path"),
            ("$ORIGIN/../lib/devkit/../devkit/share", "metadata runtime search path"),
            ("$ORIGIN/$LIB", "unsupported runtime path token"),
        ):
            with self.subTest(value=value):
                self.elf(runpath=value)
                result = self.check()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, result.stderr)

    def test_accepts_private_runtime_directory_and_its_alias(self):
        (self.prefix / "lib/devkit/lib").mkdir(parents=True)
        (self.prefix / "lib/runtime-alias").symlink_to("devkit/lib")
        self.elf(runpath="$ORIGIN/../lib/runtime-alias")
        self.assertEqual(self.check().returncode, 0, self.check().stderr)

    def test_audits_only_owned_files_and_requires_record(self):
        self.elf(runpath="$ORIGIN/../lib")
        self.elf("bin/dependency", runpath="/build/dependency", old=True)
        self.record("probe", ["bin/probe"])
        self.record("dependency", ["bin/dependency"])
        result = self.check("probe")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotEqual(self.check().returncode, 0)
        result = self.check("missing")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("expected one installed record", result.stderr)
        self.record("missing-file", ["bin/absent"])
        self.assertIn("missing package file", self.check("missing-file").stderr)

    def test_public_development_interfaces_are_rejected(self):
        for name in (
            "include/foo-1/foo.h",
            "lib/pkgconfig/foo.pc",
            "lib/cmake/foo/FooConfig.cmake",
            "share/cmake/foo/FooConfig.cmake",
            "lib/libfoo.a",
        ):
            path = self.prefix / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"fixture")
        (self.prefix / "lib/libfoo.so").symlink_to("libfoo.so.1")
        errors = AUDIT.check_prefix(self.prefix)
        self.assertEqual(sum("public development interface" in e for e in errors), 4)
        self.assertEqual(sum("public link-time interface" in e for e in errors), 2)

    def test_development_links_allow_dependency_targets_after_install(self):
        development = self.prefix / "lib/devkit/lib"
        development.mkdir(parents=True)
        runtime = self.prefix / "lib/devkit/lib/libfoo.so.1"
        runtime.write_bytes(b"runtime")
        link = development / "libfoo.so"
        link.symlink_to("libfoo.so.1")
        self.record("devel", ["lib/devkit/lib/libfoo.so"])
        self.record("runtime", ["lib/devkit/lib/libfoo.so.1"])
        self.assertEqual(self.check("devel").returncode, 0)
        runtime.unlink()
        self.assertIn("broken development link", self.check("devel").stderr)
        link.unlink()
        link.symlink_to("/usr/lib/libfoo.so.1")
        self.assertIn("non-relocatable development link", self.check("devel").stderr)

    def test_runtime_elf_belongs_in_private_lib_or_libexec(self):
        self.elf("lib/devkit/lib/libfoo.so.1", runpath="$ORIGIN")
        self.elf("lib/devkit/libexec/foo/bin/helper", runpath="$ORIGIN/../../../lib")
        self.assertEqual(self.check().returncode, 0, self.check().stderr)
        self.elf("lib/devkit/include/metadata/probe", runpath="$ORIGIN")
        self.assertIn("runtime ELF in metadata directory", self.check().stderr)

    def test_public_soname_aliases_are_only_allowed_for_dirty(self):
        runtime = self.elf("lib/devkit/lib/libfoo.so.1", runpath="$ORIGIN")
        alias = self.prefix / "lib/libfoo.so.1"
        alias.symlink_to("devkit/lib/libfoo.so.1")
        self.assertIn("public runtime library", self.check().stderr)
        self.assertEqual(
            AUDIT.check_prefix(self.prefix, allow_seed_runtime_aliases=True), []
        )
        alias.unlink()
        shutil.copyfile(runtime, alias)
        self.assertTrue(
            any(
                "public runtime library" in e
                for e in AUDIT.check_prefix(
                    self.prefix, allow_seed_runtime_aliases=True
                )
            )
        )

    def test_sysroot_and_archived_inputs_do_not_exempt_runtime_payload(self):
        for name in (
            "x86_64-pc-linux-gnu/sysroot/usr/lib64/gconv/module.so",
            "x86_64-conda-linux-gnu/sysroot/usr/lib64/gconv/module.so",
            "etc/conda/test-files/probe/0/input",
        ):
            self.elf(name, runpath="/build/original", old=True)
        self.assertEqual(self.check().returncode, 0)
        self.elf("lib/runtime-plugin/module.so", runpath="/build/original", old=True)
        result = self.check()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("lib/runtime-plugin/module.so", result.stderr)
        self.assertNotIn("sysroot", result.stderr)

    def test_invalid_owned_paths_are_rejected(self):
        self.assertTrue(
            AUDIT.check_prefix(self.prefix, ["../outside", "/etc/passwd", ""])
        )


if __name__ == "__main__":
    unittest.main()
