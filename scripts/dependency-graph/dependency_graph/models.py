from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

DEPENDENCY_KINDS = ("build", "host", "run", "run_constrained")


@dataclass(frozen=True)
class RenderedOutput:
    """One package output produced by rattler-build's renderer."""

    name: str
    version: str
    build_string: str
    recipe: str
    target_platform: str
    bootstrap: bool
    requirements: dict[str, list[str]] = field(default_factory=dict)


@dataclass(frozen=True)
class DependencyEdge:
    provider: str
    consumer: str
    kind: str
    requirement: str


@dataclass(frozen=True)
class GraphNode:
    output: RenderedOutput
    external_dependencies: dict[str, list[str]] = field(default_factory=dict)

    @property
    def name(self) -> str:
        return self.output.name


@dataclass
class DependencyGraph:
    nodes: dict[str, GraphNode] = field(default_factory=dict)
    edges: list[DependencyEdge] = field(default_factory=list)


@dataclass(frozen=True)
class RenderOptions:
    root: str
    target_platform: str
    channels: tuple[str, ...]
    variant_config: str
    variant_recipes: frozenset[str]
    rattler_build: str


def json_safe(value: Any) -> Any:
    """Return a deterministic JSON representation for graph reports."""

    if isinstance(value, dict):
        return {str(key): json_safe(value[key]) for key in sorted(value)}
    if isinstance(value, (list, tuple)):
        return [json_safe(item) for item in value]
    return value
