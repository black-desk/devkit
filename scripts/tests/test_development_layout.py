"""Check development staging preserves runtime paths and input packages."""

import json
from pathlib import Path
import shutil
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
        (self.prefix / "lib/pkgconfig").mkdir(parents=True)
        (self.prefix / "include/foo-1").mkdir(parents=True)
        (self.prefix / "include/foo-1/foo.h").write_text("int foo(void);\n")
        (self.prefix / "lib/libfoo.so.1.2").write_bytes(b"runtime fixture")
        (self.prefix / "lib/libfoo.so.1").symlink_to("libfoo.so.1.2")
        (self.prefix / "lib/libfoo.so").symlink_to("libfoo.so.1.2")
        (self.prefix / "lib/libfoo.a").write_bytes(b"archive fixture")
        (self.prefix / "lib/pkgconfig/foo.pc").write_text(
            f"prefix={self.prefix}\nlibdir=${{prefix}}/lib\n"
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

    def test_inputs_remain_untouched(self):
        (self.prefix / "conda-meta").mkdir()
        owned = [
            "include/foo-1/foo.h",
            "lib/libfoo.so",
            "lib/libfoo.so.1",
            "lib/libfoo.so.1.2",
            "lib/libfoo.a",
            "lib/pkgconfig/foo.pc",
        ]
        (self.prefix / "conda-meta/input.json").write_text(json.dumps({"files": owned}))
        self.stage()
        for path in owned:
            self.assertTrue((self.prefix / path).exists(), path)
        self.assertFalse((self.prefix / "lib/devkit").exists())

    def test_pkgconfig_without_prefix(self):
        pc = self.prefix / "lib/pkgconfig/foo.pc"
        pc.write_text("libdir=${prefix}/lib\nincludedir=${prefix}/include/foo-1\n")
        self.stage()
        self.assertIn(
            "prefix=${pcfiledir}/../..",
            (self.prefix / "lib/devkit/lib/pkgconfig/foo.pc").read_text(),
        )

    def test_pkgconfig_spaced_assignments(self):
        pc = self.prefix / "lib/pkgconfig/foo.pc"
        pc.write_text(
            f"prefix = {self.prefix}\nexec_prefix = ${{prefix}}\n"
            "libdir = ${exec_prefix}/lib\nincludedir = ${prefix}/include/foo-1\n"
        )
        self.stage()
        text = (self.prefix / "lib/devkit/lib/pkgconfig/foo.pc").read_text()
        self.assertEqual(text.count("prefix=${pcfiledir}/../.."), 1)
        self.assertNotIn(str(self.prefix), text)
        self.assertIn("exec_prefix=${prefix}", text)

    def test_exported_objects_tools_and_library_directory(self):
        objects = self.prefix / "lib/objects-Release/foo"
        objects.mkdir(parents=True)
        (objects / "foo.o").write_bytes(b"object fixture")
        (self.prefix / "bin").mkdir()
        (self.prefix / "bin/foo").write_text("tool fixture")
        config = self.prefix / "lib/cmake/foo/foo-config.cmake"
        config.parent.mkdir(parents=True)
        config.write_text(
            f"set(FOO_LIBRARY_DIR {self.prefix}/lib)\n"
            'set(TOOL "${_IMPORT_PREFIX}/bin/foo")\n'
            'set(OBJECT "${_IMPORT_PREFIX}/lib/objects-Release/foo/foo.o")\n'
        )
        self.stage()
        dev = self.prefix / "lib/devkit"
        text = (dev / "lib/cmake/foo/foo-config.cmake").read_text()
        self.assertIn(
            "set(FOO_LIBRARY_DIR ${CMAKE_CURRENT_LIST_DIR}/../../../lib)", text
        )
        self.assertIn("${_IMPORT_PREFIX}/../../bin/foo", text)
        self.assertTrue((dev / "lib/objects-Release/foo/foo.o").exists())
        self.assertFalse((dev / "bin").exists())
        relocated = self.prefix.with_name("relocated")
        self.prefix.rename(relocated)
        if shutil.which("cmake"):
            probe = relocated / "check.cmake"
            probe.write_text(
                f'set(_IMPORT_PREFIX "{relocated}/lib/devkit")\n'
                f'include("{relocated}/lib/devkit/lib/cmake/foo/foo-config.cmake")\n'
                "find_library(FOO NAMES foo HINTS ${FOO_LIBRARY_DIR} NO_DEFAULT_PATH REQUIRED)\n"
                'if(NOT EXISTS "${TOOL}" OR NOT EXISTS "${OBJECT}")\n'
                '  message(FATAL_ERROR "missing relocated export")\nendif()\n'
            )
            subprocess.run(["cmake", "-P", str(probe)], check=True)

    def test_icu_make_metadata_separates_link_and_runtime_paths(self):
        metadata = self.prefix / "lib/icu/78.3/Makefile.inc"
        metadata.parent.mkdir(parents=True)
        metadata.write_text(
            "libdir = ${exec_prefix}/lib\n"
            "ICULIBS_BASE = -L$(libdir)\n"
            "CPPFLAGS = -I$(prefix)/include/icu-78.3\n"
            "includedir = ${prefix}/include/icu-78.3\n"
            "pkglibdir = $(libdir)/icu/78.3\n"
            "RPATHLDFLAGS = $(LD_RPATH)$(libdir)\n"
        )
        self.stage()
        text = (self.prefix / "lib/devkit/lib/icu/78.3/Makefile.inc").read_text()
        self.assertIn("ICULIBS_BASE = -L$(prefix)/lib/devkit/lib", text)
        self.assertIn("CPPFLAGS = -I$(prefix)/lib/devkit/include/icu-78.3", text)
        self.assertIn("pkglibdir = $(prefix)/lib/devkit/lib/icu/78.3", text)
        self.assertIn("RPATHLDFLAGS = $(LD_RPATH)$(libdir)", text)

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
