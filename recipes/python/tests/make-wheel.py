"""Create a local wheel to test uv tool installation without a package index."""

from pathlib import Path
from zipfile import ZipFile

metadata = "devkit_python_probe-1.0.0.dist-info"
files = {
    "devkit_python_probe.py": (
        "import sys\n"
        "def main():\n"
        "    assert sys.version_info[:3] == (3, 14, 8)\n"
        "    print(sys.version.split()[0])\n"
    ),
    f"{metadata}/METADATA": (
        "Metadata-Version: 2.3\n"
        "Name: devkit-python-probe\n"
        "Version: 1.0.0\n"
        "Requires-Python: >=3.14,<3.15\n"
    ),
    f"{metadata}/WHEEL": (
        "Wheel-Version: 1.0\nRoot-Is-Purelib: true\nTag: py3-none-any\n"
    ),
    f"{metadata}/entry_points.txt": (
        "[console_scripts]\ndevkit-python-probe = devkit_python_probe:main\n"
    ),
}
record = f"{metadata}/RECORD"
files[record] = "".join(f"{name},,\n" for name in [*files, record])
Path("wheels").mkdir()
with ZipFile("wheels/devkit_python_probe-1.0.0-py3-none-any.whl", "w") as wheel:
    for name, contents in files.items():
        wheel.writestr(name, contents)
