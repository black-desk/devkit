"""Exercise stage handoffs and CI failure/skip behavior without compiling packages."""

import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "channel_artifact", ROOT / "scripts/channel-artifact.py"
)
ARTIFACT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ARTIFACT)


class ArtifactTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / "seed-packages.tsv").write_text("fixed seed\n")
        self.plan = self.root / "plan.json"
        self.plan.write_text(
            json.dumps(
                {
                    "head_sha": "abc",
                    "valid": True,
                    "selected": [{"recipe": "recipes/compiler", "bootstrap": True}],
                    "bootstrap_required": True,
                    "ordinary_recipes": [],
                }
            )
        )
        self.addCleanup(patch.stopall)
        patch.object(ARTIFACT, "ROOT", self.root).start()
        patch.object(ARTIFACT, "head", return_value="abc").start()
        patch.object(
            ARTIFACT,
            "bootstrap_digest",
            side_effect=lambda: ARTIFACT.digest(self.root / "seed-packages.tsv"),
        ).start()
        self.channel = self.root / "dirty"
        self.make_channel(self.channel)
        ARTIFACT.seal(self.channel, "dirty", self.plan, [])

    def make_channel(self, path):
        for subdir in ("linux-64", "noarch"):
            (path / subdir).mkdir(parents=True)
            (path / subdir / "repodata.json").write_text("{}")
        (path / "linux-64/pkg.conda").write_bytes(b"package")
        (path / "stage-packages.txt").write_text("linux-64/pkg.conda\n")

    def test_portable_channel_and_parent_handoff(self):
        moved = self.root / "another-runner" / "dirty"
        moved.parent.mkdir()
        shutil.move(self.channel, moved)
        ARTIFACT.verify(moved, "dirty", self.plan)
        result = self.root / "result"
        self.make_channel(result)
        ARTIFACT.seal(result, "result", self.plan, [("dirty", moved)])
        state = ARTIFACT.verify(result, "result", self.plan)
        self.assertEqual(
            state["inputs"],
            {"dirty": ARTIFACT.digest(moved / "stage-state.json")},
        )
        self.assertNotIn(str(self.root), (result / "stage-state.json").read_text())

    def test_rejects_tampered_missing_and_extra_files(self):
        package = self.channel / "linux-64/pkg.conda"
        for mutate, restore in (
            (
                lambda: package.write_bytes(b"tampered"),
                lambda: package.write_bytes(b"package"),
            ),
            (package.unlink, lambda: package.write_bytes(b"package")),
            (
                lambda: (self.channel / "noarch/extra.conda").touch(),
                lambda: (self.channel / "noarch/extra.conda").unlink(),
            ),
            (
                lambda: (self.channel / "noarch/repodata.json").write_text(
                    '{"changed": true}'
                ),
                lambda: (self.channel / "noarch/repodata.json").write_text("{}"),
            ),
        ):
            mutate()
            with self.assertRaises(ValueError):
                ARTIFACT.verify(self.channel, "dirty", self.plan)
            restore()
        ARTIFACT.verify(self.channel, "dirty", self.plan)

    def test_bootstrap_reuse_across_commits_and_plans_requires_same_inputs(
        self,
    ):
        with self.assertRaises(ValueError):
            ARTIFACT.verify(self.channel, "selfhost", self.plan)
        original = json.loads(self.plan.read_text())
        with patch.object(ARTIFACT, "head", return_value="different"):
            # The current plan must still match the current checkout.
            with self.assertRaises(ValueError):
                ARTIFACT.verify(self.channel, "dirty", self.plan)
            self.plan.write_text(json.dumps({**original, "head_sha": "different"}))
            ARTIFACT.verify(self.channel, "dirty", self.plan)
        self.plan.write_text(json.dumps(original) + "\n")
        ARTIFACT.verify(self.channel, "dirty", self.plan)
        with patch.object(ARTIFACT, "bootstrap_digest", return_value="changed-inputs"):
            with self.assertRaisesRegex(ValueError, "bootstrap input"):
                ARTIFACT.verify(self.channel, "dirty", self.plan)
        (self.root / "seed-packages.tsv").write_text("different seed\n")
        with self.assertRaises(ValueError):
            ARTIFACT.verify(self.channel, "dirty", self.plan)

    def test_ordinary_is_still_bound_to_current_commit_and_plan(self):
        recipe = self.root / "recipes/first"
        recipe.mkdir(parents=True)
        (recipe / "recipe.yaml").touch()
        report = json.loads(self.plan.read_text())
        report.update(
            bootstrap_required=False,
            ordinary_recipes=["first"],
            selected=[{"recipe": "recipes/first", "bootstrap": False}],
        )
        self.plan.write_text(json.dumps(report))
        ARTIFACT.seal(self.channel, "ordinary", self.plan, [])
        ARTIFACT.verify(self.channel, "ordinary", self.plan)
        self.plan.write_text(self.plan.read_text() + "\n")
        with self.assertRaisesRegex(ValueError, "commit/plan"):
            ARTIFACT.verify(self.channel, "ordinary", self.plan)
        report["head_sha"] = "new"
        self.plan.write_text(json.dumps(report))
        with patch.object(ARTIFACT, "head", return_value="new"):
            with self.assertRaisesRegex(ValueError, "commit/plan"):
                ARTIFACT.verify(self.channel, "ordinary", self.plan)

    def test_rejects_missing_parents_and_escaping_manifest(self):
        with self.assertRaises(ValueError):
            ARTIFACT.seal(self.channel, "selfhost", self.plan, [])
        (self.channel / "stage-packages.txt").write_text("../outside.conda\n")
        with self.assertRaises(ValueError):
            ARTIFACT.seal(self.channel, "dirty", self.plan, [])

    def test_failed_merge_preserves_destination(self):
        destination = self.root / "destination"
        destination.mkdir()
        sentinel = destination / "keep"
        sentinel.touch()
        (self.channel / "linux-64/pkg.conda").unlink()
        with self.assertRaises(ValueError):
            ARTIFACT.merge(destination, self.plan, [("dirty", self.channel)])
        self.assertTrue(sentinel.exists())

    def test_publication_rejects_mixed_selfhost_attempts(self):
        recipe = self.root / "recipes/first"
        recipe.mkdir(parents=True)
        (recipe / "recipe.yaml").touch()
        report = json.loads(self.plan.read_text())
        report["selected"].append({"recipe": "recipes/first", "bootstrap": False})
        report["ordinary_recipes"] = ["first"]
        self.plan.write_text(json.dumps(report))
        ARTIFACT.seal(self.channel, "dirty", self.plan, [])
        result = self.root / "result"
        self.make_channel(result)
        ARTIFACT.seal(result, "result", self.plan, [("dirty", self.channel)])
        selfhost = self.root / "selfhost"
        self.make_channel(selfhost)
        ARTIFACT.seal(selfhost, "selfhost", self.plan, [("result", result)])
        ordinary = self.root / "ordinary"
        self.make_channel(ordinary)
        (ordinary / "linux-64/pkg.conda").rename(ordinary / "linux-64/first.conda")
        (ordinary / "stage-packages.txt").write_text("linux-64/first.conda\n")
        ARTIFACT.seal(ordinary, "ordinary", self.plan, [("selfhost", selfhost)])
        # Each artifact is valid, but ordinary was built from a different attempt.
        (selfhost / "linux-64/pkg.conda").write_bytes(b"new build")
        ARTIFACT.seal(selfhost, "selfhost", self.plan, [("result", result)])
        with self.assertRaisesRegex(ValueError, "different stage attempts"):
            ARTIFACT.merge(
                self.root / "publication",
                self.plan,
                [("selfhost", selfhost), ("ordinary", ordinary)],
            )


class PipelineTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / "scripts").mkdir()
        for name in (
            "bootstrap.sh",
            "build-ordinary.sh",
            "affected-plan.sh",
            "channel-artifact.py",
            "bootstrap-fingerprint.py",
            "clean-build-outputs.py",
            "test-bootstrap-stage.sh",
        ):
            shutil.copy2(ROOT / "scripts" / name, self.root / "scripts" / name)
        (self.root / "bootstrap-order.json").write_text('["llvm-libgcc", "cmake"]')
        (self.root / "seed-packages.tsv").write_text("fixed seed")
        for name in ("llvm-libgcc", "cmake", "first", "second"):
            path = self.root / "recipes" / name
            path.mkdir(parents=True)
            (path / "recipe.yaml").touch()
        (self.root / "variants").mkdir()
        for stage in ("dirty", "result"):
            (self.root / "variants" / f"{stage}.yaml").write_text(stage)
        for name in ("pixi.toml", "pixi.lock"):
            (self.root / name).write_text("locked tools")
        self.log = self.root / "calls.jsonl"
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.env = {
            **os.environ,
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "PIPELINE_LOG": str(self.log),
            "PIPELINE_ROOT": str(self.root),
        }
        self.write_script(
            self.bin / "rattler-build",
            """#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args=sys.argv[1:]
with open(os.environ['PIPELINE_LOG'],'a') as stream:
 stream.write(json.dumps({'tool':'rattler-build','args':args,'tests':os.environ.get('DEVKIT_RUN_TESTS')})+'\\n')
if args[0]=='test':
 sys.exit(int(os.environ.get('FAIL_PACKAGE_TEST','0')))
recipe=Path(args[args.index('--recipe')+1]).parent.name
output=Path(args[args.index('--output-dir')+1])/'linux-64'
output.mkdir(parents=True,exist_ok=True)
(output/(recipe+'.conda')).write_text(recipe)
""",
        )
        self.write_script(
            self.bin / "rattler-index",
            """#!/usr/bin/env python3
import sys
from pathlib import Path
args=sys.argv[1:]
root=Path(args[1]); subdir=args[args.index('--target-platform')+1]
(root/subdir).mkdir(parents=True,exist_ok=True)
(root/subdir/'repodata.json').write_text('{}')
""",
        )
        for name in ("mamba", "curl"):
            self.write_script(self.bin / name, "#!/bin/sh\nprintf '%s\\n' '{}'\n")
        self.write_script(
            self.root / "scripts/fetch-seed.sh",
            """#!/bin/sh
mkdir -p "$PIPELINE_ROOT/channels/seed/noarch"
printf tzdata > "$PIPELINE_ROOT/channels/seed/noarch/tzdata-test.conda"
""",
        )
        for name in ("check-seed.sh", "check-result.sh"):
            self.write_script(
                self.root / "scripts" / name,
                """#!/bin/bash
python3 - "$0" "$@" <<'PY'
import json,os,sys
with open(os.environ['PIPELINE_LOG'],'a') as stream:
 stream.write(json.dumps({'tool':os.path.basename(sys.argv[1]),'args':sys.argv[2:]})+'\\n')
PY
""",
            )
        (self.root / "scripts/seed-libgcc-variant.py").write_text("print('{}')")
        self.run_cmd(["git", "init", "-q"])
        self.run_cmd(["git", "add", "."])
        self.run_cmd(
            [
                "git",
                "-c",
                "user.name=Pipeline Test",
                "-c",
                "user.email=test@example.invalid",
                "-c",
                "commit.gpgsign=false",
                "commit",
                "-qm",
                "fixture",
            ]
        )
        self.head = self.run_cmd(["git", "rev-parse", "HEAD"]).stdout.strip()
        self.plan = self.root / "plan.json"
        self.env["PLAN_FILE"] = str(self.plan)
        self.set_plan(True, [])

    def write_script(self, path, text):
        path.write_text(text)
        path.chmod(0o755)

    def run_cmd(self, args, check=True, extra=None):
        return subprocess.run(
            args,
            cwd=self.root,
            env={**self.env, **(extra or {})},
            check=check,
            text=True,
            capture_output=True,
        )

    def set_plan(self, bootstrap, ordinary):
        selected = [{"bootstrap": True, "recipe": "recipes/cmake"}] if bootstrap else []
        selected += [{"bootstrap": False, "recipe": "recipes/" + r} for r in ordinary]
        self.plan.write_text(
            json.dumps(
                {
                    "head_sha": self.head,
                    "valid": True,
                    "bootstrap_required": bootstrap,
                    "ordinary_recipes": ordinary,
                    "selected": selected,
                }
            )
        )

    def stage(self, name, check=True, extra=None):
        return self.run_cmd(
            ["bash", "scripts/bootstrap.sh", name], check=check, extra=extra
        )

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_stage_inputs_tests_and_immutable_selfhost(self):
        self.stage("dirty")
        # Result must work on a fresh runner with only the transferred dirty channel.
        shutil.rmtree(self.root / "channels/seed")
        self.stage("result")
        shutil.rmtree(self.root / "channels/dirty")
        self.stage("selfhost")
        artifact = self.root / "channels/result-rebuild/stage-state.json"
        before = artifact.read_bytes()
        self.stage("test")
        self.assertEqual(artifact.read_bytes(), before)
        builds = [
            c
            for c in self.calls()
            if c["tool"] == "rattler-build" and c["args"][0] == "build"
        ]
        self.assertEqual([c["tests"] for c in builds], ["0", "0", "0", "0", "1", "1"])
        for i, call in enumerate(builds):
            args = call["args"]
            channels = [args[j + 1] for j, a in enumerate(args) if a == "--channel"]
            expected = (
                ["dirty", "seed"] if i < 2 else ["dirty"] if i < 4 else ["result"]
            )
            self.assertEqual(
                channels, [str(self.root / "channels" / p) for p in expected]
            )
            self.assertEqual(args[args.index("--test") + 1], "skip")
        package_tests = [
            c
            for c in self.calls()
            if c["tool"] == "rattler-build" and c["args"][0] == "test"
        ]
        self.assertEqual(len(package_tests), 2)
        self.assertTrue(
            all(
                "result-rebuild" in c["args"][c["args"].index("--channel") + 1]
                for c in package_tests
            )
        )

    def test_bad_input_stops_before_clearing_output(self):
        self.stage("dirty")
        output = self.root / "channels/result"
        output.mkdir()
        sentinel = output / "keep"
        sentinel.touch()
        (self.root / "channels/dirty/linux-64/cmake.conda").write_text("corrupt")
        before = len(self.calls())
        self.assertNotEqual(self.stage("result", check=False).returncode, 0)
        self.assertEqual(len(self.calls()), before)
        self.assertTrue(sentinel.exists())

    def test_retry_only_clears_its_own_stage(self):
        self.stage("dirty")
        sibling = self.root / "channels/result"
        sibling.mkdir()
        sentinel = sibling / "keep"
        sentinel.touch()
        self.stage("dirty")
        self.assertTrue(sentinel.exists())

    def test_local_all_entry_promotes_only_after_tests(self):
        self.stage("all")
        self.assertTrue((self.root / "channels/result/linux-64/cmake.conda").is_file())
        self.assertTrue(
            (self.root / "channels/result/noarch/tzdata-test.conda").is_file()
        )
        calls = self.calls()
        self.assertEqual(
            len(
                [
                    c
                    for c in calls
                    if c["tool"] == "rattler-build" and c["args"][0] == "test"
                ]
            ),
            2,
        )

    def test_package_test_failure_propagates(self):
        for stage in ("dirty", "result", "selfhost"):
            self.stage(stage)
        self.assertNotEqual(
            self.stage(
                "test", check=False, extra={"FAIL_PACKAGE_TEST": "1"}
            ).returncode,
            0,
        )

    def test_ordinary_only_uses_overlay_and_online_baseline(self):
        self.set_plan(False, ["first", "second"])
        self.run_cmd(["bash", "scripts/build-ordinary.sh"])
        builds = [c for c in self.calls() if c["tool"] == "rattler-build"]
        self.assertEqual(len(builds), 2)
        for call in builds:
            args = call["args"]
            channels = [args[j + 1] for j, a in enumerate(args) if a == "--channel"]
            self.assertEqual(
                channels,
                [
                    str(self.root / "channels/ordinary"),
                    "https://prefix.dev/black-desk",
                ],
            )
        self.assertEqual(
            (self.root / "channels/ordinary/stage-packages.txt")
            .read_text()
            .splitlines(),
            ["linux-64/first.conda", "linux-64/second.conda"],
        )

    def test_ordinary_after_bootstrap_preserves_selfhost_input(self):
        self.set_plan(True, ["first"])
        for stage in ("dirty", "result", "selfhost", "test"):
            self.stage(stage)
        state = self.root / "channels/result-rebuild/stage-state.json"
        before = state.read_bytes()
        self.run_cmd(["bash", "scripts/build-ordinary.sh"])
        self.assertEqual(state.read_bytes(), before)
        args = [c for c in self.calls() if c["tool"] == "rattler-build"][-1]["args"]
        self.assertEqual(
            [args[j + 1] for j, a in enumerate(args) if a == "--channel"],
            [
                str(self.root / "channels/ordinary"),
                str(self.root / "channels/result-rebuild"),
                "https://prefix.dev/black-desk",
            ],
        )
        self.assertFalse(
            (self.root / "channels/ordinary/linux-64/cmake.conda").exists()
        )
        self.run_cmd(
            [
                "python3",
                "scripts/channel-artifact.py",
                "merge",
                "--plan",
                str(self.plan),
                "--channel",
                "channels/publication",
                "--input",
                "selfhost",
                "channels/result-rebuild",
                "--input",
                "ordinary",
                "channels/ordinary",
            ]
        )
        self.assertEqual(
            {
                p.name
                for p in (self.root / "channels/publication/linux-64").glob("*.conda")
            },
            {"llvm-libgcc.conda", "cmake.conda", "first.conda"},
        )
        self.assertEqual(state.read_bytes(), before)

    def test_cached_selfhost_from_prior_commit_runs_tests_and_builds_ordinary(
        self,
    ):
        self.set_plan(True, ["first"])
        for stage in ("dirty", "result", "selfhost", "test"):
            self.stage(stage)
        state = self.root / "channels/result-rebuild/stage-state.json"
        before = state.read_bytes()
        self.run_cmd(
            [
                "git",
                "-c",
                "user.name=Pipeline Test",
                "-c",
                "user.email=test@example.invalid",
                "-c",
                "commit.gpgsign=false",
                "commit",
                "--allow-empty",
                "-qm",
                "ordinary-only follow-up",
            ]
        )
        self.head = self.run_cmd(["git", "rev-parse", "HEAD"]).stdout.strip()
        self.set_plan(True, ["first"])
        # Only the cached selfhost channel is transferred to the new runner.
        for name in ("seed", "dirty", "result"):
            shutil.rmtree(self.root / "channels" / name)
        self.log.write_text("")
        self.stage("test")
        self.run_cmd(["bash", "scripts/build-ordinary.sh"])
        self.run_cmd(
            [
                "python3",
                "scripts/channel-artifact.py",
                "merge",
                "--plan",
                str(self.plan),
                "--channel",
                "channels/publication",
                "--input",
                "selfhost",
                "channels/result-rebuild",
                "--input",
                "ordinary",
                "channels/ordinary",
            ]
        )
        calls = [c for c in self.calls() if c["tool"] == "rattler-build"]
        self.assertTrue(any(c["args"][0] == "test" for c in calls))
        builds = [c for c in calls if c["args"][0] == "build"]
        self.assertEqual(len(builds), 1)
        self.assertIn(str(self.root / "recipes/first/recipe.yaml"), builds[0]["args"])
        self.assertEqual(state.read_bytes(), before)

    def plan_from_report(self, report):
        directory = self.root / "scripts/dependency-graph"
        directory.mkdir()
        self.write_script(directory / "graph", '#!/bin/sh\ncat "$PLANNER_REPORT"\n')
        report_file = self.root / "report.json"
        report_file.write_text(json.dumps(report))
        output = self.root / "github-output"
        result = self.run_cmd(
            ["bash", "scripts/affected-plan.sh", self.head],
            check=False,
            extra={
                "PLANNER_REPORT": str(report_file),
                "GITHUB_OUTPUT": str(output),
            },
        )
        return result, output

    def test_plan_has_commit_control_outputs_and_ordered_unique_recipes(self):
        report = {
            "valid": True,
            "global_change": False,
            "changed_recipes": ["recipes/cmake"],
            "selected": [
                {"bootstrap": True, "recipe": "recipes/cmake", "reasons": []},
                {"bootstrap": False, "recipe": "recipes/first", "reasons": []},
                {"bootstrap": False, "recipe": "recipes/first", "reasons": []},
                {"bootstrap": False, "recipe": "recipes/second", "reasons": []},
            ],
        }
        result, output = self.plan_from_report(report)
        self.assertEqual(result.returncode, 0, result.stderr)
        plan = json.loads(self.plan.read_text())
        self.assertEqual(plan["head_sha"], self.head)
        self.assertEqual(plan["ordinary_recipes"], ["first", "second"])
        self.assertEqual(
            output.read_text().splitlines(),
            [
                "bootstrap_required=true",
                "ordinary_required=true",
                "build_required=true",
            ],
        )

    def test_empty_plan_skips_all_builds(self):
        result, output = self.plan_from_report({"valid": True, "selected": []})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            output.read_text().splitlines(),
            [
                "bootstrap_required=false",
                "ordinary_required=false",
                "build_required=false",
            ],
        )

    def test_invalid_plan_fails_before_control_outputs(self):
        result, output = self.plan_from_report({"valid": False, "selected": []})
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(output.exists())


class JobGateTests(unittest.TestCase):
    def setUp(self):
        workflow = (ROOT / ".github/workflows/packages.yml").read_text()
        script = workflow.split("python3 - <<'PY'\n", 1)[1].rsplit("          PY", 1)[0]
        import textwrap

        self.script = textwrap.dedent(script)

    def gate(self, bootstrap, ordinary, overrides=None, *, cache_hit=False):
        jobs = {
            "plan": {
                "result": "success",
                "outputs": {
                    "bootstrap_required": str(bootstrap).lower(),
                    "bootstrap_build_required": str(
                        bootstrap and not cache_hit
                    ).lower(),
                    "ordinary_required": str(ordinary).lower(),
                },
            }
        }
        for name in ("dirty", "result", "selfhost", "smoke", "ordinary"):
            required = ordinary if name == "ordinary" else bootstrap
            if name in ("dirty", "result", "selfhost") and cache_hit:
                required = False
            jobs[name] = {"result": "success" if required else "skipped"}
        for name, result in (overrides or {}).items():
            jobs[name]["result"] = result
        return subprocess.run(
            [sys.executable, "-c", self.script],
            env={**os.environ, "NEEDS_JSON": json.dumps(jobs)},
            capture_output=True,
        ).returncode

    def test_intentional_skip_combinations(self):
        for bootstrap in (False, True):
            for ordinary in (False, True):
                self.assertEqual(self.gate(bootstrap, ordinary), 0)

    def test_cache_hit_skips_only_compile_jobs(self):
        self.assertEqual(self.gate(True, True, cache_hit=True), 0)
        self.assertEqual(self.gate(True, False, cache_hit=True), 0)
        for job in ("smoke", "ordinary"):
            for result in ("skipped", "failure", "cancelled"):
                self.assertNotEqual(
                    self.gate(True, True, {job: result}, cache_hit=True), 0
                )
        self.assertNotEqual(
            self.gate(True, True, {"dirty": "success"}, cache_hit=True), 0
        )

    def test_failure_cancellation_and_dependency_skip_fail_gate(self):
        for stage in (
            "plan",
            "dirty",
            "result",
            "selfhost",
            "smoke",
            "ordinary",
        ):
            for result in ("failure", "cancelled", "skipped"):
                self.assertNotEqual(self.gate(True, True, {stage: result}), 0)


if __name__ == "__main__":
    unittest.main()
