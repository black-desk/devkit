from __future__ import annotations

import shutil
import os
import io
import json
from contextlib import redirect_stdout, redirect_stderr
import subprocess
import tempfile
import unittest
from dataclasses import replace
from pathlib import Path

from dependency_graph.models import RenderOptions, RenderedOutput
from dependency_graph.plan import calculate_plan, repository_plan
from dependency_graph.rattler import RenderError, _requirements, build_graph


def output(name, recipe=None, **kwargs):
    return RenderedOutput(
        name=name,
        version="1",
        build_string="h1234567_0",
        recipe=recipe or f"recipes/{name}",
        target_platform="linux-64",
        bootstrap=False,
        **kwargs,
    )


class PlanTests(unittest.TestCase):
    def plan(self, old, new, changed):
        return calculate_plan(
            build_graph(old), build_graph(new), set(changed), False, []
        )

    def test_unchanged_consumer_needs_bump_even_with_removed_edge(self):
        a = output("a")
        b = output("b", requirements={"host": ["a >=1"]})
        report = self.plan(
            [a, b],
            [
                replace(a, build_number=1, build_string="h1234567_1"),
                replace(b, requirements={}),
            ],
            ["recipes/a"],
        )
        self.assertFalse(report["valid"])
        self.assertEqual({i["package"] for i in report["selected"]}, {"a", "b"})

    def test_new_provider_and_consumer_and_version_change(self):
        a = output("a")
        b = output("b", requirements={"host": ["a"]})
        report = self.plan([], [a, b], ["recipes/a", "recipes/b"])
        self.assertTrue(report["valid"])
        self.assertEqual([i["package"] for i in report["selected"]], ["a", "b"])
        self.assertTrue(
            self.plan([a], [replace(a, version="2")], ["recipes/a"])["valid"]
        )

    def test_number_must_increase_and_change_filename(self):
        a = replace(output("a"), build_number=2, build_string="h1234567_2")
        for number, string in [
            (1, "h1234567_1"),
            (2, "h7654321_2"),
            (3, "h1234567_2"),
        ]:
            with self.subTest(number=number, string=string):
                self.assertFalse(
                    self.plan(
                        [a],
                        [replace(a, build_number=number, build_string=string)],
                        ["recipes/a"],
                    )["valid"]
                )

    def test_sibling_outputs_are_atomic_and_both_checked(self):
        a = output("a", "recipes/pair")
        b = output("b", "recipes/pair", requirements={"host": ["z"]})
        z = output("z")
        report = self.plan([], [a, b, z], ["recipes/pair", "recipes/z"])
        self.assertEqual([i["package"] for i in report["selected"]], ["z", "a", "b"])
        report = self.plan([a, b, z], [a, b, replace(z, version="2")], ["recipes/z"])
        self.assertEqual(len([i for i in report["selected"] if i["error"]]), 2)

    def test_recipe_level_cycle_rejected(self):
        a = output("a", "recipes/pair")
        b = output("b", "recipes/pair", requirements={"host": ["c"]})
        c = output("c", requirements={"host": ["a"]})
        with self.assertRaisesRegex(ValueError, "cycle"):
            self.plan([], [a, b, c], ["recipes/pair", "recipes/c"])

    def test_removed_output_rejected(self):
        with self.assertRaisesRegex(RenderError, "deletion"):
            self.plan([output("a")], [], ["recipes/a"])

    def test_unsolved_requirements_include_tests_pins_exports(self):
        reqs = _requirements(
            {
                "recipe": {
                    "package": {"name": "a"},
                    "requirements": {
                        "host": ["b >=1"],
                        "run_constraints": ["c <2"],
                        "run": [{"pin_subpackage": {"name": "d", "exact": True}}],
                        "run_exports": {"strong": ["a >=1", "e >=2"]},
                    },
                    "tests": [{"requirements": {"run": ["test-tool"]}}],
                }
            }
        )
        graph = build_graph(
            [output("a", requirements=reqs)]
            + [output(n) for n in ["b", "c", "d", "e", "test-tool"]]
        )
        self.assertEqual(
            {e.provider for e in graph.edges}, {"b", "c", "d", "e", "test-tool"}
        )

    @unittest.skipUnless(
        shutil.which("rattler-build") and shutil.which("rattler-index"),
        "rattler tools are needed",
    )
    def test_real_renderer_unpublished_dependency_and_worktree_edits(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)

            def recipe(name, requirements=""):
                path = root / "recipes" / name
                path.mkdir(parents=True, exist_ok=True)
                (path / "recipe.yaml").write_text(
                    f'package:\n  name: devkit-plan-{name}\n  version: "1"\n'
                    "build:\n  number: 0\n  string: h${{ hash }}_${{ build_number }}\n"
                    + requirements
                )

            recipe("seed")
            (root / "bootstrap-order.json").write_text('["seed"]')
            (root / "variants").mkdir()
            (root / "variants/result.yaml").write_text("{}")

            def git(*args):
                return subprocess.run(
                    ["git", "-C", directory, *args],
                    check=True,
                    capture_output=True,
                    text=True,
                ).stdout.strip()

            git("init")
            git("add", ".")
            git(
                "-c",
                "user.name=Test",
                "-c",
                "user.email=test@example.com",
                "commit",
                "-m",
                "base",
            )
            base = git("rev-parse", "HEAD")
            recipe("lib")
            recipe("tool", "requirements:\n  host:\n    - devkit-plan-lib >=1\n")
            options = RenderOptions(
                directory,
                "linux-64",
                (),
                str(root / "variants/result.yaml"),
                frozenset(),
                "rattler-build",
            )
            report = repository_plan(options, base)
            self.assertTrue(report["valid"])
            self.assertEqual(
                [i["package"] for i in report["selected"]],
                ["devkit-plan-lib", "devkit-plan-tool"],
            )
            # Build the unpublished provider, index it, then build its consumer.
            # The consumer's script proves the host prefix contains that artifact.
            for name, script in [
                (
                    "lib",
                    'mkdir -p "$PREFIX/share/probe"; echo proof > "$PREFIX/share/probe/input"',
                ),
                (
                    "tool",
                    'test "$(cat "$PREFIX/share/probe/input")" = proof; mkdir -p "$PREFIX/share/tool"; echo ok > "$PREFIX/share/tool/result"',
                ),
            ]:
                path = root / "recipes" / name / "recipe.yaml"
                source = path.read_text().replace(
                    "  number: 0", "  number: 0\n  script: |\n    " + script
                )
                path.write_text(source)
            channel = root / "channel"
            (channel / "linux-64").mkdir(parents=True)
            (channel / "noarch").mkdir()
            env = dict(
                os.environ,
                RATTLER_CACHE_DIR=str(root / "cache"),
                XDG_CACHE_HOME=str(root / "xdg"),
            )
            for name in ["lib", "tool"]:
                subprocess.run(
                    ["rattler-index", "fs", str(channel)],
                    check=True,
                    capture_output=True,
                    env=env,
                )
                result = subprocess.run(
                    [
                        "rattler-build",
                        "build",
                        "--recipe",
                        str(root / "recipes" / name / "recipe.yaml"),
                        "--no-config",
                        "--target-platform",
                        "linux-64",
                        "--channel",
                        str(channel),
                        "--output-dir",
                        str(channel),
                    ],
                    text=True,
                    capture_output=True,
                    env=env,
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            # Generated build artifacts must not become inputs in the Git fixture.
            (root / ".gitignore").write_text("channel/\ncache/\nxdg/\n")
            git("add", ".")
            git(
                "-c",
                "user.name=Test",
                "-c",
                "user.email=test@example.com",
                "commit",
                "-m",
                "chain",
            )
            base = git("rev-parse", "HEAD")
            (root / "recipes/lib/helper.sh").write_text("echo changed\n")
            report = repository_plan(options, base)
            self.assertFalse(report["valid"])
            self.assertEqual(len(report["selected"]), 2)
            from dependency_graph.cli import main

            stdout, stderr = io.StringIO(), io.StringIO()
            with redirect_stdout(stdout), redirect_stderr(stderr):
                status = main(["plan", "--root", directory, "--check", "--json", base])
            self.assertEqual(status, 1)
            self.assertFalse(json.loads(stdout.getvalue())["valid"])
            self.assertIn("requires a larger build number", stderr.getvalue())
            for name in ["lib", "tool"]:
                path = root / "recipes" / name / "recipe.yaml"
                path.write_text(path.read_text().replace("number: 0", "number: 1"))
            self.assertTrue(repository_plan(options, base)["valid"])

    def test_global_change_checks_every_package(self):
        a = output("a")
        b = output("b")
        graph = build_graph([a, b])
        report = calculate_plan(graph, graph, set(), True, [])
        self.assertEqual(len(report["selected"]), 2)
        self.assertFalse(report["valid"])

    def test_bootstrap_selected_through_consumer_expands_generation(self):
        a = output("a")
        b = replace(output("b", requirements={"build": ["a"]}), bootstrap=True)
        c = replace(output("c"), bootstrap=True)
        d = output("d", requirements={"run": ["c"]})
        graph = build_graph([a, b, c, d])
        from dependency_graph.graph import reverse_closure

        selected, _ = reverse_closure(graph, {"a"}, {"b", "c"})
        self.assertEqual(selected, {"a", "b", "c", "d"})
        with self.assertRaisesRegex(ValueError, "bootstrap generation cannot depend"):
            calculate_plan(graph, graph, {"recipes/a"}, False, ["b", "c"])
