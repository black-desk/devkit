from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any

from .graph import non_bootstrap_cycles, reverse_closure, selected_schedule
from .models import DependencyEdge, DependencyGraph, RenderOptions, json_safe
from .rattler import (
    RenderError,
    build_graph,
    discover_recipes,
    load_bootstrap_order,
    package_name,
    render_outputs,
)

DEFAULT_VARIANT_RECIPES = frozenset({"sysroot", "gcc-toolchain", "binutils", "make"})


def repository_root() -> Path:
    return Path(__file__).resolve().parents[3]


def _options(args: argparse.Namespace) -> RenderOptions:
    root = Path(args.root).resolve()
    requested_channels = args.channel or ["channels/result"]
    channels = tuple(
        str(
            (root / channel).resolve()
            if not channel.startswith(("http://", "https://", "file://"))
            else channel
        )
        for channel in requested_channels
    )
    return RenderOptions(
        root=str(root),
        target_platform=args.target_platform,
        channels=channels,
        variant_config=str((root / args.variant_config).resolve()),
        variant_recipes=frozenset(args.variant_recipe or DEFAULT_VARIANT_RECIPES),
        rattler_build=args.rattler_build,
    )


def _resolve_roots(
    graph: DependencyGraph,
    values: list[str],
    root: Path,
) -> set[str]:
    roots: set[str] = set()
    unknown: list[str] = []
    for value in values:
        changed_path = Path(value)
        if changed_path.is_absolute():
            try:
                changed_path = changed_path.resolve().relative_to(root)
            except ValueError:
                pass
        if changed_path.name == "recipe.yaml":
            changed_path = changed_path.parent
        normalized = str(changed_path)
        matches = {
            name
            for name, node in graph.nodes.items()
            if name == value
            or node.output.recipe == normalized
            or node.output.recipe == f"recipes/{normalized}"
            or node.output.recipe.endswith(f"/{normalized}")
        }
        if matches:
            roots.update(matches)
        else:
            unknown.append(value)
    if unknown:
        raise RenderError(f"unknown package or recipe: {', '.join(unknown)}")
    return roots


def _edge_dict(edge: DependencyEdge) -> dict[str, str]:
    return {
        "provider": edge.provider,
        "consumer": edge.consumer,
        "kind": edge.kind,
        "requirement": edge.requirement,
    }


def _audit_report(graph: DependencyGraph, options: RenderOptions) -> dict[str, Any]:
    consumers: dict[str, dict[str, set[str]]] = {
        name: defaultdict(set) for name in graph.nodes
    }
    for edge in graph.edges:
        consumers[edge.provider][edge.consumer].add(edge.kind)

    nodes = []
    for name in sorted(graph.nodes):
        node = graph.nodes[name]
        output = node.output
        nodes.append(
            {
                "package": name,
                "version": output.version,
                "build_string": output.build_string,
                "recipe": output.recipe,
                "target_platform": output.target_platform,
                "bootstrap": output.bootstrap,
                "requirements": output.requirements,
                "external_dependencies": node.external_dependencies,
                "consumers": {
                    consumer: sorted(kinds)
                    for consumer, kinds in sorted(consumers[name].items())
                },
            }
        )

    return {
        "schema": "devkit-dependency-graph-audit-v1",
        "target_platform": options.target_platform,
        "channels": list(options.channels),
        "node_count": len(nodes),
        "edge_count": len(graph.edges),
        "bootstrap_generation": sorted(
            {
                node.output.recipe
                for node in graph.nodes.values()
                if node.output.bootstrap
            }
        ),
        "nodes": nodes,
        "edges": [_edge_dict(edge) for edge in graph.edges],
        "non_bootstrap_cycles": non_bootstrap_cycles(graph),
    }


def _print_audit(graph: DependencyGraph, report: dict[str, Any]) -> None:
    print(f"rendered outputs: {report['node_count']}")
    print(f"local dependency edges: {report['edge_count']}")
    print("bootstrap generation:")
    for recipe in report["bootstrap_generation"]:
        print(f"  - {recipe}")
    print("outputs:")
    for node in report["nodes"]:
        print(
            f"  - {node['package']} {node['version']} {node['build_string']} "
            f"[{node['recipe']}]"
        )
        for kind, specs in node["requirements"].items():
            print(f"      {kind}: {', '.join(specs) or '-'}")
        if node["external_dependencies"]:
            external = ", ".join(
                f"{name} ({'/'.join(specs)})"
                for name, specs in node["external_dependencies"].items()
            )
            print(f"      external: {external}")
        consumers = node["consumers"]
        if consumers:
            rendered = ", ".join(
                f"{consumer} ({'/'.join(kinds)})"
                for consumer, kinds in consumers.items()
            )
            print(f"      consumers: {rendered}")
    if report["non_bootstrap_cycles"]:
        print("non-bootstrap cycles:")
        for component in report["non_bootstrap_cycles"]:
            print(f"  - {' -> '.join(component)}")
    else:
        print("non-bootstrap cycles: none")


def _affected_report(
    graph: DependencyGraph,
    options: RenderOptions,
    requested: list[str],
) -> dict[str, Any]:
    bootstrap_order = load_bootstrap_order(options.root)
    bootstrap_names = {
        name for name, node in graph.nodes.items() if node.output.bootstrap
    }
    roots = _resolve_roots(graph, requested, Path(options.root))
    selected, reasons = reverse_closure(graph, roots, bootstrap_names)
    schedule = selected_schedule(graph, selected, bootstrap_order)
    selected_edges = [
        _edge_dict(edge)
        for edge in graph.edges
        if edge.provider in selected and edge.consumer in selected
    ]

    return {
        "schema": "devkit-affected-build-plan-v1",
        "policy": "conservative-reverse-closure",
        "requested": requested,
        "roots": sorted(roots),
        "selected": [
            {
                "package": name,
                "recipe": graph.nodes[name].output.recipe,
                "bootstrap": graph.nodes[name].output.bootstrap,
                "reasons": reasons.get(name, []),
            }
            for name in schedule
        ],
        "selected_edges": selected_edges,
    }


def _print_affected(report: dict[str, Any]) -> None:
    print("policy: conservative reverse closure")
    print("changed roots:")
    for name in report["roots"]:
        print(f"  - {name}")
    print("build order:")
    for index, item in enumerate(report["selected"], start=1):
        reasons = ", ".join(item["reasons"])
        print(f"  {index}. {item['package']} [{item['recipe']}] ({reasons})")


def _add_render_arguments(parser: argparse.ArgumentParser, root: Path) -> None:
    parser.add_argument("--root", default=str(root), help="repository root")
    parser.add_argument("--target-platform", default="linux-64")
    parser.add_argument(
        "--channel",
        action="append",
        default=None,
        help="channel visible while rendering; may be repeated",
    )
    parser.add_argument(
        "--variant-config",
        default="variants/result.yaml",
        help="stage variant used for the final Linux generation",
    )
    parser.add_argument(
        "--variant-recipe",
        action="append",
        default=None,
        help="recipe that receives --variant-config; may be repeated",
    )
    parser.add_argument("--rattler-build", default="rattler-build")
    parser.add_argument("--json", action="store_true", help="emit JSON instead of text")


def build_parser() -> argparse.ArgumentParser:
    root = repository_root()
    parser = argparse.ArgumentParser(
        prog="dependency-graph",
        description="Audit the rendered devkit package dependency graph.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    audit = subparsers.add_parser("audit", help="render and audit every recipe")
    _add_render_arguments(audit, root)

    affected = subparsers.add_parser(
        "affected", help="calculate a conservative rebuild closure"
    )
    _add_render_arguments(affected, root)
    affected.add_argument(
        "changed",
        nargs="+",
        help="changed package output name or recipe directory/path",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    options = _options(args)

    try:
        outputs, _recipes = render_outputs(options)
        graph = build_graph(outputs)
        cycles = non_bootstrap_cycles(graph)
        if cycles:
            raise RenderError(
                "non-bootstrap strongly connected components: "
                + "; ".join(" -> ".join(component) for component in cycles)
            )

        if args.command == "audit":
            report = _audit_report(graph, options)
            if args.json:
                print(json.dumps(json_safe(report), indent=2, sort_keys=True))
            else:
                _print_audit(graph, report)
        else:
            report = _affected_report(graph, options, args.changed)
            if args.json:
                print(json.dumps(json_safe(report), indent=2, sort_keys=True))
            else:
                _print_affected(report)
        return 0
    except (RenderError, OSError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
