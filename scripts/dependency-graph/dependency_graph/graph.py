from __future__ import annotations

from collections import defaultdict, deque

from .models import DependencyGraph, DependencyEdge


def strongly_connected_components(graph: DependencyGraph) -> list[list[str]]:
    """Return SCCs using Tarjan's algorithm.

    Components are sorted deterministically for stable audit output.
    """

    adjacency: dict[str, set[str]] = {name: set() for name in graph.nodes}
    for edge in graph.edges:
        adjacency[edge.provider].add(edge.consumer)

    index = 0
    indices: dict[str, int] = {}
    low_links: dict[str, int] = {}
    on_stack: set[str] = set()
    stack: list[str] = []
    components: list[list[str]] = []

    def visit(node: str) -> None:
        nonlocal index
        indices[node] = low_links[node] = index
        index += 1
        stack.append(node)
        on_stack.add(node)

        for consumer in sorted(adjacency[node]):
            if consumer not in indices:
                visit(consumer)
                low_links[node] = min(low_links[node], low_links[consumer])
            elif consumer in on_stack:
                low_links[node] = min(low_links[node], indices[consumer])

        if low_links[node] == indices[node]:
            component: list[str] = []
            while True:
                member = stack.pop()
                on_stack.remove(member)
                component.append(member)
                if member == node:
                    break
            components.append(sorted(component))

    for node in sorted(graph.nodes):
        if node not in indices:
            visit(node)

    return sorted(components, key=lambda item: (item[0], item[1:]))


def non_bootstrap_cycles(graph: DependencyGraph) -> list[list[str]]:
    self_loops = {edge.provider for edge in graph.edges if edge.provider == edge.consumer}
    return [
        component
        for component in strongly_connected_components(graph)
        if (
            len(component) > 1
            and not all(graph.nodes[name].output.bootstrap for name in component)
        )
        or (
            len(component) == 1
            and component[0] in self_loops
            and not graph.nodes[component[0]].output.bootstrap
        )
    ]


def reverse_closure(
    graph: DependencyGraph,
    roots: set[str],
    bootstrap_names: set[str],
) -> tuple[set[str], dict[str, list[str]]]:
    """Select roots and every direct or transitive consumer."""

    # A bootstrap input can affect generation ordering as a whole, so selecting
    # one member selects the explicit bootstrap generation.
    if roots & bootstrap_names:
        roots |= bootstrap_names

    consumers: dict[str, set[str]] = defaultdict(set)
    for edge in graph.edges:
        consumers[edge.provider].add(edge.consumer)

    selected = set(roots)
    reasons: dict[str, list[str]] = {name: ["changed root"] for name in sorted(roots)}
    queue: deque[str] = deque(sorted(roots))
    while queue:
        provider = queue.popleft()
        for consumer in sorted(consumers[provider]):
            if consumer in selected:
                continue
            selected.add(consumer)
            reasons[consumer] = [f"depends on {provider}"]
            queue.append(consumer)

    for name in reasons:
        reasons[name].sort()
    return selected, reasons


def selected_schedule(
    graph: DependencyGraph,
    selected: set[str],
    bootstrap_order: list[str],
) -> list[str]:
    """Topologically schedule selected outputs with bootstrap as one node."""

    bootstrap_names = {name for name, node in graph.nodes.items() if node.output.bootstrap}
    selected_bootstrap = selected & bootstrap_names
    if selected_bootstrap:
        selected |= bootstrap_names

    supernodes: set[str] = set()
    representation: dict[str, str] = {}
    for name in selected:
        supernode = "__bootstrap_generation__" if name in bootstrap_names else name
        supernodes.add(supernode)
        representation[name] = supernode

    adjacency: dict[str, set[str]] = {name: set() for name in supernodes}
    indegree: dict[str, int] = {name: 0 for name in supernodes}
    for edge in graph.edges:
        if edge.provider not in selected or edge.consumer not in selected:
            continue
        provider = representation[edge.provider]
        consumer = representation[edge.consumer]
        if provider == consumer or consumer in adjacency[provider]:
            continue
        adjacency[provider].add(consumer)
        indegree[consumer] += 1

    ready = deque(sorted(name for name, degree in indegree.items() if degree == 0))
    ordered_supernodes: list[str] = []
    while ready:
        node = ready.popleft()
        ordered_supernodes.append(node)
        for consumer in sorted(adjacency[node]):
            indegree[consumer] -= 1
            if indegree[consumer] == 0:
                ready.append(consumer)

    if len(ordered_supernodes) != len(supernodes):
        raise ValueError("selected graph contains a cycle outside the bootstrap generation")

    bootstrap_outputs_by_recipe_name: dict[str, list[str]] = {}
    for name in bootstrap_names:
        if name not in selected:
            continue
        recipe_name = graph.nodes[name].output.recipe.rsplit("/", 1)[-1]
        bootstrap_outputs_by_recipe_name.setdefault(recipe_name, []).append(name)
    for names in bootstrap_outputs_by_recipe_name.values():
        names.sort()

    result: list[str] = []
    for supernode in ordered_supernodes:
        if supernode == "__bootstrap_generation__":
            for recipe in bootstrap_order:
                result.extend(bootstrap_outputs_by_recipe_name.get(recipe, []))
        else:
            result.append(supernode)
    return result
