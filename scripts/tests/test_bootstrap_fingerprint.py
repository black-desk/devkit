"""Check that bootstrap cache identity follows inputs rather than commits."""

import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "fingerprint", ROOT / "scripts/bootstrap-fingerprint.py"
)
FINGERPRINT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(FINGERPRINT)


class FingerprintTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        self.write("bootstrap-order.json", '["compiler"]')
        for name in ("pixi.toml", "pixi.lock", "seed-packages.tsv"):
            self.write(name, "fixed")
        self.write("recipes/compiler/recipe.yaml", "source:\n  - path: ../../shared\n")
        self.write("recipes/compiler/fix.patch", "patch")
        self.write("shared/input", "local source")
        self.write("recipes/ordinary/recipe.yaml", "ordinary")
        self.write("scripts/bootstrap.sh", "build")
        self.write("scripts/packaging/check.py", "audit")
        self.write("variants/dirty.yaml", "variant")
        self.write(".github/workflows/packages.yml", "runner and modes")
        self.write(".gitignore", "__pycache__/\noutput/\n")

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def digest(self):
        return FINGERPRINT.fingerprint(self.root)

    def test_ordinary_docs_generated_files_and_commit_do_not_change_key(self):
        before = self.digest()
        self.write("recipes/ordinary/recipe.yaml", "changed")
        self.write("docs/guide.md", "documentation")
        self.write("output/ignored", "generated")
        self.write("scripts/__pycache__/cached.pyc", "generated")
        subprocess.run(["git", "-C", str(self.root), "add", "."], check=True)
        subprocess.run(
            [
                "git",
                "-C",
                str(self.root),
                "-c",
                "user.name=Test",
                "-c",
                "user.email=test@example.invalid",
                "-c",
                "commit.gpgsign=false",
                "commit",
                "-qm",
                "fixture",
            ],
            check=True,
        )
        self.assertEqual(self.digest(), before)

    def test_bootstrap_sources_scripts_variants_tools_and_workflow_invalidate(
        self,
    ):
        for name in (
            "bootstrap-order.json",
            "seed-packages.tsv",
            "pixi.toml",
            "pixi.lock",
            "recipes/compiler/recipe.yaml",
            "recipes/compiler/fix.patch",
            "shared/input",
            "scripts/bootstrap.sh",
            "scripts/packaging/check.py",
            "variants/dirty.yaml",
            ".github/workflows/packages.yml",
        ):
            with self.subTest(name=name):
                path = self.root / name
                original = path.read_text()
                before = self.digest()
                path.write_text(original + "\n")
                self.assertNotEqual(self.digest(), before)
                path.write_text(original)

    def test_new_removed_and_executable_inputs_invalidate(self):
        before = self.digest()
        path = self.write("recipes/compiler/new.patch", "new patch")
        self.assertNotEqual(self.digest(), before)
        path.unlink()
        self.assertEqual(self.digest(), before)
        path = self.root / "scripts/bootstrap.sh"
        path.chmod(0o755)
        self.assertNotEqual(self.digest(), before)
        path.chmod(0o644)
        subprocess.run(["git", "-C", str(self.root), "add", "."], check=True)
        path.unlink()
        with self.assertRaises(OSError):
            self.digest()

    def test_unsupported_or_external_sources_fail_closed(self):
        for value in ("${{ version }}", "|", "/tmp", "missing"):
            with self.subTest(value=value):
                self.write("recipes/compiler/recipe.yaml", "source:\n  path: " + value)
                with self.assertRaises(ValueError):
                    self.digest()
        self.write("recipes/compiler/recipe.yaml", "source: {path: ../../shared}")
        with self.assertRaises(ValueError):
            self.digest()
        self.write("recipes/compiler/recipe.yaml", "source: {}")
        (self.root / "recipes/compiler/link").symlink_to("/etc/hosts")
        with self.assertRaises(ValueError):
            self.digest()


if __name__ == "__main__":
    unittest.main()
