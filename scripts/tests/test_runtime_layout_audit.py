"""Distinguish installed runtime ELFs from archived Rattler test inputs."""

from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
CHECK = ROOT / "scripts/check-development-layout.py"


@unittest.skipUnless(shutil.which("cc") and shutil.which("readelf"), "needs ELF tools")
class RuntimeLayoutAuditTests(unittest.TestCase):
    def test_test_inputs_do_not_exempt_runtime_payload(self):
        with tempfile.TemporaryDirectory() as directory:
            prefix = Path(directory) / "prefix"
            archived = prefix / "etc/conda/test-files/example/0/probe"
            archived.parent.mkdir(parents=True)
            source = Path(directory) / "probe.c"
            source.write_text("int main(void) { return 0; }\n")
            subprocess.run(
                ["cc", str(source), "-Wl,-rpath,/build/temporary", "-o", str(archived)],
                check=True,
            )
            result = subprocess.run(
                ["python3", str(CHECK), str(prefix)], capture_output=True, text=True
            )
            self.assertEqual(result.returncode, 0, result.stderr)

            runtime = prefix / "bin/example"
            runtime.parent.mkdir()
            shutil.copyfile(archived, runtime)
            result = subprocess.run(
                ["python3", str(CHECK), str(prefix)], capture_output=True, text=True
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(str(runtime), result.stderr)
            self.assertIn("/build/temporary", result.stderr)
            self.assertNotIn(str(archived), result.stderr)
