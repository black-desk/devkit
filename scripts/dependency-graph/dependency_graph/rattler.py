from __future__ import annotations

import json
import re
import subprocess
import tempfile
from pathlib import Path
from typing import Any

from .models import (
    DEPENDENCY_KINDS,
    DependencyEdge,
    DependencyGraph,
    GraphNode,
    RenderOptions,
    RenderedOutput,
)


class RenderError(RuntimeError):
    """Raised when rattler-build cannot render a recipe."""


_PACKAGE_NAME = re.compile(r"^(?:[A-Za-z0-9_.-]+::)?([A-Za-z0-9_][A-Za-z0-9_.-]*)")


def package_name(spec: Any) -> str | None:
    """Extract the canonical package name from a rendered MatchSpec.

    The renderer is responsible for evaluating recipe selectors and Jinja.  This
    function only extracts the name from the already-rendered specification.
    """

    if isinstance(spec, dict):
        if isinstance(spec.get("source"), str):
            spec = spec["source"]
        elif isinstance(spec.get("spec"), str):
            spec = spec["spec"]
        elif isinstance(spec.get("pin_compatible"), dict):
            spec = spec["pin_compatible"]["name"]
        elif isinstance(spec.get("pin_subpackage"), dict):
            spec = spec["pin_subpackage"]["name"]
        elif isinstance(spec.get("pin_subpackage"), str):
            spec = spec["pin_subpackage"]
        else:
            return None
    if not isinstance(spec, str):
        return None

    match = _PACKAGE_NAME.match(spec.strip())
    return match.group(1) if match else None


def rendered_spec(spec: Any) -> str:
    """Return a stable textual form for a rendered dependency."""

    if isinstance(spec, str):
        return spec
    if isinstance(spec, dict):
        for key in ("source", "spec", "pin_subpackage"):
            if isinstance(spec.get(key), str):
                return spec[key]
        name = package_name(spec)
        if name:
            return name
        return json.dumps(spec, sort_keys=True, separators=(",", ":"))
    return str(spec)


def discover_recipes(root: str | Path) -> list[Path]:
    recipe_root = Path(root) / "recipes"
    return sorted(recipe_root.glob("*/recipe.yaml"))


def load_bootstrap_order(root: str | Path) -> list[str]:
    path = Path(root) / "bootstrap-order.json"
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise RenderError(f"cannot load {path}: {exc}") from exc

    if (
        not isinstance(value, list)
        or not value
        or not all(isinstance(item, str) and item for item in value)
    ):
        raise RenderError(f"{path} must be a non-empty JSON array of recipe names")
    if len(value) != len(set(value)):
        raise RenderError(f"{path} contains duplicate recipe names")

    recipes = discover_recipes(root)
    names = {path.parent.name for path in recipes}
    missing = [name for name in value if name not in names]
    if missing:
        raise RenderError(f"bootstrap recipe(s) not found: {', '.join(missing)}")
    return value


def _extract_rendered_array(stdout: str) -> list[dict[str, Any]]:
    lines = stdout.splitlines()
    for index, line in enumerate(lines):
        if not line.startswith("["):
            continue
        try:
            value = json.loads("\n".join(lines[index:]))
        except json.JSONDecodeError:
            continue
        if isinstance(value, list):
            return value
    raise RenderError("rattler-build did not emit a rendered recipe JSON array")


def _error_details(stdout: str, stderr: str) -> str:
    details: list[str] = []
    for stream in (stderr, stdout):
        tail = stream.strip().splitlines()[-12:]
        if tail:
            details.append("\n".join(tail))
    return "\n".join(dict.fromkeys(details))


def _requirements(payload: dict[str, Any]) -> dict[str, list[str]]:
    recipe = payload.get("recipe", {})
    raw = recipe.get("requirements") or {}
    requirements = {}
    for kind in ("build", "host", "run", "run_constraints", "run_constrained"):
        specs = raw.get(kind) or []
        if specs:
            requirements["run_constrained" if kind == "run_constraints" else kind] = [
                rendered_spec(spec) for spec in specs
            ]
    for test in recipe.get("tests", []):
        for specs in (test.get("requirements") or {}).values():
            requirements.setdefault("test", []).extend(rendered_spec(s) for s in specs)
    # Include declared exports conservatively, even when an ignore rule would
    # remove them at solve time. Self exports need no extra graph edge.
    exports = raw.get("run_exports") or {}
    if isinstance(exports, list):
        exports = {"weak": exports}
    requirements["run_exports"] = [
        rendered_spec(spec)
        for specs in exports.values()
        for spec in specs
        if package_name(spec) != recipe.get("package", {}).get("name")
    ]
    return {kind: specs for kind, specs in requirements.items() if specs}


def _render_one(
    recipe: Path,
    options: RenderOptions,
    render_output_root: str,
) -> list[dict[str, Any]]:
    command = [
        options.rattler_build,
        "build",
        "--recipe",
        str(recipe.resolve()),
        "--render-only",
        "--target-platform",
        options.target_platform,
        "--channel-priority",
        "strict",
        "--log-style",
        "json",
        "--no-config",
        "--output-dir",
        render_output_root,
    ]
    if recipe.parent.name in options.variant_recipes:
        command.extend(
            ("--variant-config", str(Path(options.variant_config).resolve()))
        )
    for channel in options.channels:
        command.extend(("--channel", channel))

    result = subprocess.run(
        command,
        check=False,
        text=True,
        capture_output=True,
    )
    if result.returncode != 0:
        raise RenderError(
            f"failed to render {recipe} (exit {result.returncode}):\n"
            f"{_error_details(result.stdout, result.stderr)}"
        )
    return _extract_rendered_array(result.stdout)


def render_outputs(
    options: RenderOptions,
) -> tuple[list[RenderedOutput], list[Path]]:
    recipes = discover_recipes(options.root)
    if not recipes:
        raise RenderError(f"no recipes found below {Path(options.root) / 'recipes'}")

    bootstrap = set(load_bootstrap_order(options.root))
    outputs: list[RenderedOutput] = []

    # Rattler-Build always adds its output directory as an implicit channel.
    # Keep that channel empty so graph rendering sees only the explicit inputs.
    with tempfile.TemporaryDirectory(
        prefix="devkit-graph-render-"
    ) as render_output_root:
        for recipe in recipes:
            payloads = _render_one(recipe, options, render_output_root)
            for payload in payloads:
                package = payload.get("recipe", {}).get("package", {})
                build = payload.get("recipe", {}).get("build", {})
                configuration = payload.get("build_configuration", {})
                name = package.get("name")
                if not isinstance(name, str) or not name:
                    raise RenderError(
                        f"{recipe} rendered an output without a package name"
                    )
                outputs.append(
                    RenderedOutput(
                        name=name,
                        version=str(package.get("version", "")),
                        build_string=str(build.get("string", "")),
                        recipe=str(recipe.parent.relative_to(Path(options.root))),
                        target_platform=str(
                            configuration.get(
                                "target_platform", options.target_platform
                            )
                        ),
                        bootstrap=recipe.parent.name in bootstrap,
                        build_number=int(build.get("number", 0)),
                        requirements=_requirements(payload),
                    )
                )

    outputs.sort(
        key=lambda item: (
            item.recipe,
            item.name,
            item.version,
            item.build_string,
        )
    )
    return outputs, recipes


def build_graph(outputs: list[RenderedOutput]) -> DependencyGraph:
    by_name: dict[str, GraphNode] = {}
    for output in outputs:
        if output.name in by_name:
            previous = by_name[output.name].output
            raise RenderError(
                f"duplicate package output {output.name!r}: "
                f"{previous.recipe} and {output.recipe}"
            )
        by_name[output.name] = GraphNode(output=output)

    edges: list[DependencyEdge] = []
    seen_edges: set[tuple[str, str, str, str]] = set()
    for output in outputs:
        node = by_name[output.name]
        for kind in DEPENDENCY_KINDS:
            for rendered_spec in output.requirements.get(kind, []):
                provider_name = package_name(rendered_spec)
                if provider_name is None:
                    raise RenderError(
                        f"cannot determine dependency name in {output.recipe}: {rendered_spec}"
                    )
                provider = by_name.get(provider_name)
                if provider is None:
                    node.external_dependencies.setdefault(provider_name, []).append(
                        str(rendered_spec)
                    )
                    continue
                edge = DependencyEdge(
                    provider=provider_name,
                    consumer=output.name,
                    kind=kind,
                    requirement=str(rendered_spec),
                )
                key = (
                    edge.provider,
                    edge.consumer,
                    edge.kind,
                    edge.requirement,
                )
                if key not in seen_edges:
                    seen_edges.add(key)
                    edges.append(edge)

    for node in by_name.values():
        for specs in node.external_dependencies.values():
            specs[:] = sorted(set(specs))

    edges.sort(
        key=lambda edge: (
            edge.provider,
            edge.consumer,
            edge.kind,
            edge.requirement,
        )
    )
    return DependencyGraph(nodes=by_name, edges=edges)
