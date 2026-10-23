from __future__ import annotations

import json
import subprocess
import tempfile
from dataclasses import replace
from pathlib import Path
from typing import Any

from .graph import non_bootstrap_cycles, reverse_closure, selected_schedule
from .models import DependencyGraph, RenderOptions
from .rattler import (
    RenderError,
    build_graph,
    load_bootstrap_order,
    render_outputs,
)

GLOBAL_INPUTS = {
    "bootstrap-order.json",
    "seed-packages.tsv",
    "retired-packages.json",
    "pixi.toml",
    "pixi.lock",
    ".github/workflows/packages.yml",
    ".gitignore",
    ".gitmodules",
}


def load_retired_packages(root: str) -> frozenset[str]:
    path = Path(root) / "retired-packages.json"
    if not path.exists():
        return frozenset()
    try:
        names = json.loads(path.read_text())
    except (OSError, ValueError) as exc:
        raise RenderError(f"cannot load {path}: {exc}") from exc
    if (
        not isinstance(names, list)
        or not all(isinstance(name, str) and name for name in names)
        or len(names) != len(set(names))
    ):
        raise RenderError(f"{path} must contain unique package names")
    return frozenset(names)


def git(root: str, *args: str) -> str:
    return subprocess.check_output(["git", "-C", root, *args], text=True).strip()


def revision_error(old: Any, new: Any) -> str | None:
    if old is None:
        return None
    if old.version == new.version:
        if new.build_number <= old.build_number:
            return "same version requires a larger build number"
        if old.build_string == new.build_string:
            return "build string must change with the build number"
    return None


def calculate_plan(
    before: DependencyGraph,
    current: DependencyGraph,
    changed: set[str],
    full: bool,
    bootstrap_order: list[str],
    retired: frozenset[str] = frozenset(),
) -> dict[str, Any]:
    cycles = non_bootstrap_cycles(current)
    if cycles:
        raise RenderError(f"non-bootstrap dependency cycles: {cycles}")
    missing = {node.output.recipe for node in before.nodes.values()} - {
        node.output.recipe for node in current.nodes.values()
    }
    removed = set(before.nodes) - set(current.nodes)
    still_present = retired & set(current.nodes)
    if still_present:
        raise RenderError(
            "retired outputs are still present: " + ", ".join(sorted(still_present))
        )
    unsupported_recipes = {
        recipe
        for recipe in missing
        if any(
            name not in retired
            for name, node in before.nodes.items()
            if node.output.recipe == recipe
        )
    }
    unsupported_outputs = removed - retired
    if unsupported_recipes or unsupported_outputs:
        raise RenderError(
            "recipe/output deletion or rename is unsupported: "
            + ", ".join(sorted(unsupported_recipes | unsupported_outputs))
        )
    # Old edges participate only in impact analysis. Scheduling uses the new
    # graph, so changing dependency direction cannot create an artificial cycle.
    merged = DependencyGraph(
        nodes=current.nodes,
        edges=[
            edge
            for edge in set(before.edges + current.edges)
            if edge.provider in current.nodes and edge.consumer in current.nodes
        ],
    )
    roots = {
        name
        for name, node in current.nodes.items()
        if full or node.output.recipe in changed
    }
    bootstrap = {name for name, node in current.nodes.items() if node.output.bootstrap}
    selected, reasons = reverse_closure(merged, roots, bootstrap)
    schedule = selected_schedule(current, selected, bootstrap_order)
    items = []
    for name in schedule:
        new = current.nodes[name].output
        old = before.nodes[name].output if name in before.nodes else None
        error = revision_error(old, new)
        items.append(
            {
                "package": name,
                "recipe": new.recipe,
                "bootstrap": new.bootstrap,
                "reasons": reasons.get(name, []),
                "version": new.version,
                "build_number": new.build_number,
                "build_string": new.build_string,
                "previous_version": old.version if old else None,
                "previous_build_number": old.build_number if old else None,
                "error": error,
            }
        )
    return {
        "schema": "devkit-affected-build-plan-v2",
        "retired": sorted(removed),
        "roots": sorted(roots),
        "global_change": full,
        "changed_recipes": sorted(changed),
        "selected": items,
        "valid": all(item["error"] is None for item in items),
    }


def repository_plan(options: RenderOptions, base: str) -> dict[str, Any]:
    baseline = git(options.root, "merge-base", base, "HEAD")
    paths = git(
        options.root, "diff", "--no-renames", "--name-only", "-z", baseline
    ).split("\0")
    paths += git(
        options.root, "ls-files", "--others", "--exclude-standard", "-z"
    ).split("\0")
    changed = set()
    full = False
    for path in filter(None, paths):
        # The planner and its tests schedule builds; they do not produce package
        # payloads. Their own CI tests validate changes without a channel rebuild.
        if path.startswith("scripts/dependency-graph/"):
            continue
        # Only the recipe's root README is documentation by convention. A README
        # under source/ or tests/ can be a real build or test input.
        parts = path.split("/")
        if len(parts) == 3 and parts[0] == "recipes" and parts[2] == "README.md":
            continue
        if path in GLOBAL_INPUTS or path.startswith(("variants/", "scripts/")):
            full = True
        if path.startswith("recipes/"):
            if len(parts) < 3:
                raise RenderError(f"unexpected file directly below recipes/: {path}")
            changed.add("/".join(parts[:2]))
    if not changed and not full:
        return {
            "schema": "devkit-affected-build-plan-v2",
            "base": baseline,
            "global_change": False,
            "changed_recipes": [],
            "roots": [],
            "selected": [],
            "valid": True,
        }
    # Compare missing recipes against baseline outputs below, where the
    # explicit retirement manifest can authorize removal of every output.
    current = build_graph(render_outputs(options)[0])
    with tempfile.TemporaryDirectory(prefix="devkit-plan-base-") as directory:
        archive = subprocess.run(
            [
                "git",
                "-C",
                options.root,
                "archive",
                baseline,
                "recipes",
                "variants",
                "bootstrap-order.json",
            ],
            check=True,
            capture_output=True,
        )
        subprocess.run(["tar", "-x", "-C", directory], input=archive.stdout, check=True)
        variant_relative = Path(options.variant_config).relative_to(options.root)
        previous_options = replace(
            options,
            root=directory,
            variant_config=str(Path(directory) / variant_relative),
        )
        before = build_graph(render_outputs(previous_options)[0])
    report = calculate_plan(
        before,
        current,
        changed,
        full,
        load_bootstrap_order(options.root),
        load_retired_packages(options.root),
    )
    report["base"] = baseline
    return report
