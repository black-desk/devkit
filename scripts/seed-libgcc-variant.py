#!/usr/bin/env python3
"""Emit compatibility variants from the authoritative seed archive metadata."""

import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
records = {}
for line in (root / "seed-packages.tsv").read_text().splitlines():
    if not line or line.startswith("#"):
        continue
    subdir, archive, *_ = line.split("\t")
    repodata = json.loads(
        (root / "channels/seed" / subdir / "repodata.json").read_text()
    )
    record = repodata["packages.conda"][archive]
    if record["name"] in records:
        raise SystemExit(f'duplicate seed package: {record["name"]}')
    records[record["name"]] = record
runtime = records["libgcc"]
required = f'libgcc =={runtime["version"]} {runtime["build"]}'
if required not in records["libstdcxx"]["depends"]:
    raise SystemExit(
        "seed libstdcxx/libgcc pin changed; review compatibility before proceeding"
    )
# JSON is also a YAML variant configuration; values are singleton axes.
print(
    json.dumps(
        {
            "seed_libgcc_version": [runtime["version"]],
            "seed_libgcc_build": [runtime["build"]],
            "seed_libgcc_build_number": [runtime["build_number"]],
        },
        indent=2,
    )
)
