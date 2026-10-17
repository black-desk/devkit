#!/usr/bin/env python3
"""Validate plans and seal portable channel artifacts between CI stages."""

import argparse
import hashlib
import importlib.util
import json
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STAGES = ("dirty", "result", "selfhost", "ordinary")


# Keep the standalone scripts importable without changing runner PYTHONPATH.
SPEC = importlib.util.spec_from_file_location(
    "bootstrap_fingerprint", ROOT / "scripts/bootstrap-fingerprint.py"
)
FINGERPRINT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(FINGERPRINT)


def bootstrap_digest():
    return FINGERPRINT.fingerprint(ROOT)


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def head():
    return subprocess.check_output(
        ["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True
    ).strip()


def validate_plan(path):
    plan = json.loads(path.read_text())
    if plan.get("head_sha") != head() or plan.get("valid") is not True:
        raise ValueError("plan belongs to another commit or has invalid revisions")
    selected = plan["selected"]
    if any(item.get("error") is not None for item in selected):
        raise ValueError("plan contains invalid package revisions")
    bootstrap = any(item["bootstrap"] for item in selected)
    ordinary = list(
        dict.fromkeys(
            item["recipe"].removeprefix("recipes/")
            for item in selected
            if not item["bootstrap"]
        )
    )
    if plan["bootstrap_required"] != bootstrap or plan["ordinary_recipes"] != ordinary:
        raise ValueError("plan control fields disagree with selected packages")
    for recipe in ordinary:
        if "/" in recipe or not (ROOT / "recipes" / recipe / "recipe.yaml").is_file():
            raise ValueError(f"invalid recipe in plan: {recipe}")
    return plan


def expected_parents(stage, plan):
    if stage == "result":
        return {"dirty"}
    if stage == "selfhost":
        return {"result"}
    if stage == "ordinary" and plan["bootstrap_required"]:
        return {"selfhost"}
    return set()


def channel_files(channel):
    files = []
    for subdir in ("linux-64", "noarch"):
        directory = channel / subdir
        if not (directory / "repodata.json").is_file():
            raise ValueError(f"missing {subdir}/repodata.json")
        files.extend(p for p in directory.iterdir() if p.is_file())
    files.append(channel / "stage-packages.txt")
    if not files[-1].is_file():
        raise ValueError("missing stage package manifest")
    if any(p.is_symlink() for p in files):
        raise ValueError("channel artifacts must contain real files, not symlinks")
    return {
        str(p.relative_to(channel)): {
            "size": p.stat().st_size,
            "sha256": digest(p),
        }
        for p in sorted(files)
    }


def validate_manifest(channel):
    entries = (channel / "stage-packages.txt").read_text().splitlines()
    if not entries or len(entries) != len(set(entries)):
        raise ValueError("empty or duplicate package manifest")
    for entry in entries:
        path = Path(entry)
        if (
            len(path.parts) != 2
            or path.parts[0] not in ("linux-64", "noarch")
            or path.suffix != ".conda"
            or not (channel / path).is_file()
        ):
            raise ValueError(f"invalid or missing package: {entry}")


def verify(channel, stage, plan):
    report = validate_plan(plan)
    state = json.loads((channel / "stage-state.json").read_text())
    if (
        state["schema"] != 2
        or state["stage"] != stage
        or state["seed_manifest_sha256"] != digest(ROOT / "seed-packages.tsv")
    ):
        raise ValueError("channel stage/seed provenance mismatch")
    if stage == "ordinary":
        if state["head_sha"] != head() or state["plan_sha256"] != digest(plan):
            raise ValueError("channel commit/plan provenance mismatch")
    elif state["bootstrap_input_sha256"] != bootstrap_digest():
        raise ValueError("channel bootstrap input provenance mismatch")
    if set(state["inputs"]) != expected_parents(stage, report):
        raise ValueError("channel has incorrect input stage provenance")
    if state["files"] != channel_files(channel):
        raise ValueError("channel files are missing, unexpected or corrupted")
    validate_manifest(channel)
    return state


def seal(channel, stage, plan, inputs):
    report = validate_plan(plan)
    if {parent for parent, _ in inputs} != expected_parents(stage, report):
        raise ValueError("incorrect input stages for channel artifact")
    validate_manifest(channel)
    parents = {}
    for expected, path in inputs:
        verify(path, expected, plan)
        parents[expected] = digest(path / "stage-state.json")
    state = {
        "schema": 2,
        "stage": stage,
        "head_sha": head(),
        "plan_sha256": digest(plan),
        "seed_manifest_sha256": digest(ROOT / "seed-packages.tsv"),
        "bootstrap_input_sha256": (bootstrap_digest() if stage != "ordinary" else None),
        "inputs": parents,
        "files": channel_files(channel),
    }
    (channel / "stage-state.json").write_text(json.dumps(state, indent=2) + "\n")


def merge(output, plan, inputs):
    # Verify all inputs before deleting the destination. Never copy stale indexes.
    report = validate_plan(plan)
    expected = set()
    if report["bootstrap_required"]:
        expected.add("selfhost")
    if report["ordinary_recipes"]:
        expected.add("ordinary")
    if not expected or {stage for stage, _ in inputs} != expected:
        raise ValueError("publication inputs disagree with the build plan")
    archives = {}
    states = {}
    for stage, channel in inputs:
        states[stage] = verify(channel, stage, plan)
        if channel.resolve() == output.resolve():
            raise ValueError("merge output must differ from its input channels")
        for subdir in ("linux-64", "noarch"):
            for archive in (channel / subdir).glob("*.conda"):
                key = f"{subdir}/{archive.name}"
                if key in archives:
                    raise ValueError(f"duplicate publication archive: {key}")
                archives[key] = archive
    for state in states.values():
        for parent, checksum in state["inputs"].items():
            for stage, channel in inputs:
                if stage == parent and digest(channel / "stage-state.json") != checksum:
                    raise ValueError(
                        "publication inputs come from different stage attempts"
                    )
    shutil.rmtree(output, ignore_errors=True)
    for subdir in ("linux-64", "noarch"):
        (output / subdir).mkdir(parents=True)
    for name, archive in archives.items():
        shutil.copy2(archive, output / name)
    for subdir in ("linux-64", "noarch"):
        subprocess.run(
            ["rattler-index", "fs", str(output), "--target-platform", subdir],
            check=True,
        )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("validate-plan", "seal", "verify", "merge"))
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--channel", type=Path)
    parser.add_argument("--stage", choices=STAGES)
    parser.add_argument(
        "--input",
        nargs=2,
        action="append",
        default=[],
        metavar=("STAGE", "CHANNEL"),
    )
    args = parser.parse_args()
    inputs = [(stage, Path(path)) for stage, path in args.input]
    if args.action == "validate-plan":
        validate_plan(args.plan)
    else:
        if args.channel is None or (args.action != "merge" and args.stage is None):
            parser.error("--channel and --stage are required for seal/verify")
        if args.action == "seal":
            seal(args.channel, args.stage, args.plan, inputs)
        elif args.action == "verify":
            verify(args.channel, args.stage, args.plan)
        else:
            merge(args.channel, args.plan, inputs)


if __name__ == "__main__":
    main()
