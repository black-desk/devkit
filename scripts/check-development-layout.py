#!/usr/bin/env python3
"""Check a completed channel using the shared recipe package audit."""

from pathlib import Path
import runpy

if __name__ == "__main__":
    runpy.run_path(
        str(Path(__file__).resolve().parent / "packaging/check-package.py"),
        run_name="__main__",
    )
