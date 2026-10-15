"""Check development staging preserves runtime paths and input packages."""

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
STAGE = ROOT / "scripts/packaging/stage-development.py"


class DevelopmentLayoutTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.prefix = Path(self.temp.name) / "prefix"
        (self.prefix / "lib/devkit/lib/pkgconfig").mkdir(parents=True)
        (self.prefix / "lib/devkit/include/foo-1").mkdir(parents=True)
        (self.prefix / "lib/devkit/include/foo-1/foo.h").write_text("int foo(void);\n")
        (self.prefix / "lib/libfoo.so.1.2").write_bytes(b"runtime fixture")
        (self.prefix / "lib/libfoo.so.1").symlink_to("libfoo.so.1.2")
        (self.prefix / "lib/libfoo.so").symlink_to("libfoo.so.1.2")
        (self.prefix / "lib/libfoo.a").write_bytes(b"archive fixture")
        (self.prefix / "lib/devkit/lib/pkgconfig/foo.pc").write_text(
            "prefix=${pcfiledir}/../..\nlibdir=${prefix}/lib\n"
            "includedir=${prefix}/include/foo-1\nName: foo\n"
        )

    def stage(self):
        subprocess.run(["python3", str(STAGE), str(self.prefix), "--all"], check=True)

    def test_runtime_plugins_and_relocation(self):
        plugins = self.prefix / "lib/ossl-modules"
        plugins.mkdir()
        (plugins / "legacy.so").write_bytes(b"plugin fixture")
        resources = self.prefix / "lib/linux"
        resources.mkdir()
        (resources / "builtins.a").write_bytes(b"compiler resource")
        (self.prefix / "lib/libgcc.a").symlink_to("linux/builtins.a")
        (self.prefix / "lib/libgcc_eh.a").symlink_to("libfoo.a")
        (self.prefix / "lib/libunwind.so").symlink_to("libfoo.so")
        self.stage()
        relocated = self.prefix.with_name("relocated")
        self.prefix.rename(relocated)
        self.assertFalse((relocated / "lib/libfoo.so").exists())
        dev = relocated / "lib/devkit"
        self.assertEqual(
            (dev / "lib/libfoo.so").resolve(),
            (relocated / "lib/libfoo.so.1.2").resolve(),
        )
        self.assertEqual(
            (dev / "lib/libfoo.so.1").resolve(),
            (relocated / "lib/libfoo.so.1").resolve(),
        )
        self.assertEqual(
            (relocated / "lib/libfoo.so.1").read_bytes(), b"runtime fixture"
        )
        self.assertEqual(
            (dev / "lib/libunwind.so").resolve(),
            (relocated / "lib/libfoo.so.1.2").resolve(),
        )
        self.assertTrue((dev / "include/foo-1/foo.h").is_file())
        self.assertTrue((dev / "lib/libfoo.a").is_file())
        self.assertEqual((dev / "lib/libgcc.a").read_bytes(), b"compiler resource")
        self.assertEqual((dev / "lib/libgcc_eh.a").read_bytes(), b"archive fixture")
        self.assertTrue((relocated / "lib/ossl-modules/legacy.so").is_file())
        self.assertIn(
            "prefix=${pcfiledir}/../..", (dev / "lib/pkgconfig/foo.pc").read_text()
        )

    def test_native_installed_metadata_and_helpers_remain_untouched(self):
        dev = self.prefix / "lib/devkit"
        (dev / "lib/pkgconfig").mkdir(parents=True, exist_ok=True)
        pc = dev / "lib/pkgconfig/native.pc"
        metadata = "prefix=${pcfiledir}/../..\nlibdir=${prefix}/lib\n"
        pc.write_text(metadata)
        (self.prefix / "bin").mkdir()
        helper = self.prefix / "bin/ncurses6-config"
        content = f'libdir="{dev}/lib"\n' f'RPATH_LIST="{self.prefix}/lib"\n'
        helper.write_text(content)
        self.stage()
        self.assertEqual(pc.read_text(), metadata)
        self.assertEqual(helper.read_text(), content)

    def test_inputs_remain_untouched(self):
        (self.prefix / "conda-meta").mkdir()
        owned = [
            "lib/devkit/include/foo-1/foo.h",
            "lib/libfoo.so",
            "lib/libfoo.so.1",
            "lib/libfoo.so.1.2",
            "lib/libfoo.a",
            "lib/devkit/lib/pkgconfig/foo.pc",
        ]
        (self.prefix / "conda-meta/input.json").write_text(json.dumps({"files": owned}))
        self.stage()
        for path in owned:
            self.assertTrue((self.prefix / path).exists(), path)
        self.assertFalse((self.prefix / "lib/devkit/lib/libfoo.a").exists())

    def test_misplaced_development_files_are_rejected(self):
        for relative in (
            "include/foo.h",
            "lib/pkgconfig/foo.pc",
            "lib/cmake/foo.cmake",
            "share/cmake/foo.cmake",
            "lib/icu/78.3/Makefile.inc",
        ):
            with self.subTest(relative=relative):
                path = self.prefix / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                content = "unmodified upstream content\n"
                path.write_text(content)
                result = subprocess.run(
                    ["python3", str(STAGE), str(self.prefix), "--all"],
                    capture_output=True,
                    text=True,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("must be installed at its final path", result.stderr)
                self.assertEqual(path.read_text(), content)
                path.unlink()

    def test_exported_objects_are_staged(self):
        objects = self.prefix / "lib/objects-Release/foo"
        objects.mkdir(parents=True)
        (objects / "foo.o").write_bytes(b"object fixture")
        self.stage()
        self.assertEqual(
            (self.prefix / "lib/devkit/lib/objects-Release/foo/foo.o").read_bytes(),
            b"object fixture",
        )

    def test_unversioned_runtime_requires_review(self):
        (self.prefix / "lib/libambiguous.so").write_bytes(b"\x7fELFfixture")
        result = subprocess.run(
            ["python3", str(STAGE), str(self.prefix), "--all"],
            capture_output=True,
            text=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unversioned runtime library needs review", result.stderr)
        self.assertTrue((self.prefix / "lib/libambiguous.so").exists())
