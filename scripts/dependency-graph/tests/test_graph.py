from __future__ import annotations

import unittest

from dependency_graph.graph import (
    non_bootstrap_cycles,
    reverse_closure,
    selected_schedule,
)
from dependency_graph.models import (
    DependencyEdge,
    DependencyGraph,
    GraphNode,
    RenderedOutput,
)


def output(
    name: str, recipe: str | None = None, bootstrap: bool = False
) -> RenderedOutput:
    return RenderedOutput(
        name=name,
        version="1.0",
        build_string="test_0",
        recipe=recipe or f"recipes/{name}",
        target_platform="linux-64",
        bootstrap=bootstrap,
    )


class GraphTests(unittest.TestCase):
    def test_package_name_extraction(self) -> None:
        from dependency_graph.rattler import package_name

        self.assertEqual(package_name("gcc ==16.2.0"), "gcc")
        self.assertEqual(package_name("conda-forge::python >=3.12"), "python")
        self.assertEqual(
            package_name({"pin_subpackage": "gcc", "spec": "gcc ==16.2.0 meta_0"}),
            "gcc",
        )

    def test_rejects_non_bootstrap_cycle(self) -> None:
        nodes = {name: GraphNode(output(name, bootstrap=False)) for name in ("a", "b")}
        graph = DependencyGraph(
            nodes=nodes,
            edges=[
                DependencyEdge("a", "b", "run", "b"),
                DependencyEdge("b", "a", "run", "a"),
            ],
        )
        self.assertEqual(non_bootstrap_cycles(graph), [["a", "b"]])

    def test_rejects_non_bootstrap_self_loop(self) -> None:
        nodes = {"a": GraphNode(output("a", bootstrap=False))}
        graph = DependencyGraph(
            nodes=nodes,
            edges=[DependencyEdge("a", "a", "run", "a")],
        )
        self.assertEqual(non_bootstrap_cycles(graph), [["a"]])

    def test_bootstrap_cycle_is_permitted(self) -> None:
        nodes = {
            name: GraphNode(output(name, bootstrap=True))
            for name in ("gcc", "binutils")
        }
        graph = DependencyGraph(
            nodes=nodes,
            edges=[
                DependencyEdge("gcc", "binutils", "build", "binutils"),
                DependencyEdge("binutils", "gcc", "build", "gcc"),
            ],
        )
        self.assertEqual(non_bootstrap_cycles(graph), [])

    def test_reverse_closure_and_bootstrap_expansion(self) -> None:
        nodes = {
            name: GraphNode(output(name, recipe=recipe, bootstrap=bootstrap))
            for name, recipe, bootstrap in (
                ("gcc", "recipes/gcc-toolchain", True),
                ("gxx", "recipes/gcc-toolchain", True),
                ("make", "recipes/make", True),
                ("ripgrep", "recipes/ripgrep", False),
                ("lazygit", "recipes/lazygit", False),
            )
        }
        graph = DependencyGraph(
            nodes=nodes,
            edges=[
                DependencyEdge("gcc", "make", "build", "make"),
                DependencyEdge("gcc", "ripgrep", "build", "ripgrep"),
                DependencyEdge("ripgrep", "lazygit", "run", "lazygit"),
            ],
        )
        selected, reasons = reverse_closure(graph, {"gcc"}, {"gcc", "make"})
        self.assertEqual(selected, {"gcc", "gxx", "make", "ripgrep", "lazygit"})
        self.assertIn("depends on gcc", reasons["ripgrep"])
        schedule = selected_schedule(graph, selected, ["gcc-toolchain", "make"])
        self.assertEqual(schedule[:3], ["gcc", "gxx", "make"])
        self.assertLess(schedule.index("ripgrep"), schedule.index("lazygit"))


if __name__ == "__main__":
    unittest.main()
