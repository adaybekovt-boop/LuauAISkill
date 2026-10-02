"""Offline protocol tests. All adapter responses here are fixtures, never real model evidence."""
from __future__ import annotations

import copy
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import run_ab as ab


def config():
    return {"generator": {"model": "test-generator", "version": "fixture-v1", "settings": {"temperature": 0}},
            "judge": {"model": "test-judge", "version": "fixture-v1", "settings": {"temperature": 0}},
            "seed": 12, "repetitions": 3, "bootstrap_samples": 1000,
            "tool_policy": {"internet": False, "maximum_tool_calls": 5}}


def grade(score=3, gate=None):
    return {"task_completed": score >= 2, "completion_verifiable": True,
            "completion_evidence": "Unit-test fixture completion assessment",
            "scores": {d: score for d in ab.DIMENSIONS}, "rationale": "Unit-test fixture grade",
            "critical_failure": {"occurred": False, "evidence": ""},
            "hard_gates": {g: {"violated": g == gate, "uncertain": False,
                               "evidence": "Fixture violation" if g == gate else ""} for g in ab.GATES}}


def response(request, source="synthetic"):
    value = {"effective": {**request["model"], "seed": request["seed"]}, "source": source,
             "isolation": {"fresh_session": True, "tool_policy_enforced": True, "private_inputs_hidden": True}}
    if request["operation"] == "generate":
        value["answer"] = "better" if request["skill_dir"] else "worse"
        value["skill_audit"] = {"collector": "adapter_tool_boundary", "complete": True,
                                "events": [{"operation": "read", "path": "SKILL.md"}] if request["skill_dir"] else []}
    else:
        value["grades"] = {label: grade(3) if c["answer"] == "better" else grade(1, "fabricated_tests")
                           for label, c in request["candidates"].items()}
    return value


class Protocol(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        self.root = self.base / "repo"
        (self.root / "evals/cases").mkdir(parents=True)
        (self.root / "SKILL.md").write_text('metadata:\n  version: "test"\n')
        (self.root / "evals/RUBRIC.md").write_text("Fixture rubric")
        cases = [{"id": f"T-{i:02}", "category": "test", "kind": "task", "lang": "en", "prompt": "Do a task",
                  "must": ["do it"], "must_not": ["fake evidence"], "critical": "wrong", "refs": ["SKILL.md"]}
                 for i in range(30)]
        (self.root / "evals/cases/test.jsonl").write_text("\n".join(json.dumps(c) for c in cases))
        (self.root / "evals/pilot.json").write_text(json.dumps([c["id"] for c in cases]))
        self.run = self.base / "run"
        self.manifest = ab.prepare(self.root, self.run, config(), "pilot")

    def tearDown(self):
        self.tmp.cleanup()

    def fill(self, source="synthetic", custom=None):
        def adapter(_command, request, _cwd, _timeout):
            value = response(request, source)
            return custom(request, value) if custom else value
        with patch.object(ab, "call_adapter", side_effect=adapter):
            ab.generate(self.run, "fixture")
            ab.judge(self.run, "fixture")

    def test_prepare_is_pending_and_network_free(self):
        result = ab.report(self.run, root=self.root)
        self.assertEqual(result["status"], "PENDING")
        self.assertIsNone(result["overall"])
        self.assertEqual(len(result["missing_artifacts"]), 360)
        self.assertEqual(result["complete_tasks"], 0)

    def test_zero_interval_is_reported_as_inconclusive(self):
        def tied(request, value):
            if request["operation"] == "judge":
                value["grades"] = {label: grade(3) for label in ("X", "Y")}
            return value
        self.fill(source="external", custom=tied)
        result = ab.report(self.run, root=self.root)
        self.assertEqual(result["overall"]["task_bootstrap_95ci"], [0.0, 0.0])
        self.assertIn("inconclusive", result["conclusion"])
        self.assertNotEqual(result["release_gate"], "PASS")

    def test_cross_run_answer_transplant_is_rejected_even_with_identical_inputs(self):
        self.fill(source="external")
        new_run = self.base / "new-run"
        new_manifest = ab.prepare(self.root, new_run, config(), "pilot")
        self.assertNotEqual(self.manifest["run_id"], new_manifest["run_id"])
        for name in ("answers", "judgments"):
            shutil.copytree(self.run / "private" / name, new_run / "private" / name)
        with self.assertRaisesRegex(ab.EvalError, "answer belongs to a different manifest"):
            ab.report(new_run, root=self.root)
        with patch.object(ab, "call_adapter", side_effect=AssertionError("no paid retry")):
            with self.assertRaisesRegex(ab.EvalError, "different manifest"):
                ab.generate(new_run, "fixture")
            with self.assertRaisesRegex(ab.EvalError, "different manifest"):
                ab.judge(new_run, "fixture")

    def test_changed_skill_cannot_reuse_old_run_artifacts(self):
        self.fill(source="external")
        (self.root / "SKILL.md").write_text('metadata:\n  version: "new-skill"\n')
        new_run = self.base / "new-skill-run"
        ab.prepare(self.root, new_run, config(), "pilot")
        self.assertTrue(all(ab.current_inputs(new_run, self.root).values()))
        for name in ("answers", "judgments"):
            shutil.copytree(self.run / "private" / name, new_run / "private" / name)
        with self.assertRaisesRegex(ab.EvalError, "answer belongs to a different manifest"):
            ab.report(new_run, root=self.root)

    def test_judgment_transplant_is_rejected_independently(self):
        self.fill(source="external")
        old_run = self.run
        new_run = self.base / "new-judgment-run"
        ab.prepare(self.root, new_run, config(), "pilot")
        self.run = new_run
        self.fill(source="external")
        shutil.copyfile(old_run / "private/judgments/T-00--1--0.json",
                        new_run / "private/judgments/T-00--1--0.json")
        with self.assertRaisesRegex(ab.EvalError, "judgment belongs to a different manifest"):
            ab.report(new_run, root=self.root)

    def test_generation_digest_reconstructs_stable_request_paths(self):
        case, repetition, key, seed = next(ab.pairs(self.manifest))
        request = ab.generation_request(self.manifest, case, seed, "skill", "/tmp/one/project", "/tmp/one/skill")
        other = ab.generation_request(self.manifest, case, seed, "skill", "/tmp/two/project", "/tmp/two/skill")
        self.assertEqual(ab.normalize_generation_request(request), ab.normalize_generation_request(other))
        self.assertEqual(ab.normalize_generation_request(request),
                         ab.generation_request(self.manifest, case, seed, "skill"))
        self.fill(source="external")
        path = ab.answer_path(self.run, key, "skill")
        artifact = ab.read_json(path)
        artifact["request_sha256"] = "0" * 64
        ab.write_json(path, artifact)
        with self.assertRaisesRegex(ab.EvalError, "generation request digest mismatch"):
            ab.report(self.run, root=self.root)

    def test_generation_request_binds_materialized_inputs(self):
        case, _repetition, _key, seed = next(ab.pairs(self.manifest))
        original = ab.generation_request(self.manifest, case, seed, "skill")
        changed_case = {**case, "initial_files": {"main.luau": "different input"}}
        self.assertNotEqual(ab.digest(original), ab.digest(ab.generation_request(self.manifest, changed_case, seed, "skill")))
        changed_manifest = {**self.manifest, "skill_sha256": "new-skill-content-hash"}
        self.assertNotEqual(ab.digest(original), ab.digest(ab.generation_request(changed_manifest, case, seed, "skill")))

    def test_new_manifest_binding_alone_cannot_hide_changed_prompt(self):
        self.fill(source="external")
        source = self.root / "evals/cases/test.jsonl"
        source.write_text(source.read_text().replace("Do a task", "Different requested task"))
        new_run = self.base / "changed-prompt-run"
        manifest = ab.prepare(self.root, new_run, config(), "pilot")
        for name in ("answers", "judgments"):
            shutil.copytree(self.run / "private" / name, new_run / "private" / name)
        for path in (new_run / "private/answers").glob("*.json"):
            artifact = ab.read_json(path)
            artifact["manifest_sha256"] = ab.digest(manifest)
            ab.write_json(path, artifact)
        with self.assertRaisesRegex(ab.EvalError, "generation request digest mismatch"):
            ab.report(new_run, root=self.root)

    def test_judge_packet_digest_is_reconstructed(self):
        self.fill(source="external")
        path = self.run / "private/judgments/T-00--1--0.json"
        artifact = ab.read_json(path)
        artifact["packet_sha256"] = "0" * 64
        ab.write_json(path, artifact)
        with self.assertRaisesRegex(ab.EvalError, "judge packet digest mismatch"):
            ab.report(self.run, root=self.root)
        with patch.object(ab, "call_adapter", side_effect=AssertionError("no paid retry")):
            with self.assertRaisesRegex(ab.EvalError, "judge packet digest mismatch"):
                ab.judge(self.run, "fixture")

    def test_artifact_identity_fields_are_verified(self):
        self.fill(source="external")
        case, repetition, key, seed = next(ab.pairs(self.manifest))
        answers = {c: ab.read_json(ab.answer_path(self.run, key, c)) for c in ab.CONDITIONS}
        for field, bad in (("key", "OTHER--1"), ("condition", "baseline"), ("repetition", True)):
            artifact = copy.deepcopy(answers["skill"])
            artifact[field] = bad
            with self.assertRaisesRegex(ab.EvalError, "answer identity mismatch"):
                ab.validate_answer_artifact(self.manifest, case, repetition, key, seed, "skill", artifact)
        original = ab.read_json(ab.judgment_path(self.run, key, 0))
        for field, bad in (("key", "OTHER--1"), ("order", 1), ("repetition", True)):
            artifact = copy.deepcopy(original)
            artifact[field] = bad
            with self.assertRaisesRegex(ab.EvalError, "judgment identity mismatch"):
                ab.validate_judgment_artifact(self.manifest, case, repetition, key, seed, 0, answers, artifact)

    def test_retained_pilot_evidence_is_rechecked(self):
        self.fill(source="external")
        full = self.base / "full"
        ab.prepare(self.root, full, config(), "full", self.run)
        path = full / "private/pilot/private/answers/T-00--1--skill.json"
        value = ab.read_json(path)
        value["response"]["answer"] = "tampered retained pilot answer"
        ab.write_json(path, value)
        with self.assertRaisesRegex(ab.EvalError, "answers changed"):
            ab.report(full, root=self.root)

    def test_negative_trigger_access_blocks_release_with_high_scores(self):
        path = self.root / "evals/cases/test.jsonl"
        path.write_text(path.read_text().replace('"kind": "task"', '"kind": "negative-trigger"'))
        other = self.base / "negative-run"
        ab.prepare(self.root, other, config(), "pilot")
        self.run = other
        self.fill(source="external")
        result = ab.report(self.run, root=self.root)
        self.assertFalse(result["release_criteria"]["negative_triggers_clean"])
        self.assertEqual(result["overall"]["negative_trigger_failure_pairs"]["skill"], 90)
        self.assertEqual(result["overall"]["skill_mean"], 0)

    def test_old_run_cannot_bless_changed_current_skill(self):
        self.fill(source="external")
        (self.root / "SKILL.md").write_text('metadata:\n  version: "changed"\n')
        result = ab.report(self.run, root=self.root)
        self.assertFalse(result["current_inputs"]["skill"])
        self.assertEqual(result["release_gate"], "BLOCKED")

    def test_current_dataset_and_rubric_are_bound(self):
        self.fill(source="external")
        (self.root / "evals/RUBRIC.md").write_text("changed")
        self.assertFalse(ab.report(self.run, root=self.root)["current_inputs"]["judge_prompt"])
        path = self.root / "evals/cases/test.jsonl"
        path.write_text(path.read_text().replace("Do a task", "Do another task"))
        self.assertFalse(ab.report(self.run, root=self.root)["current_inputs"]["dataset"])

    def test_template_config_is_not_configured_evidence(self):
        with self.assertRaisesRegex(ab.EvalError, "placeholder"):
            ab.validate_config(ab.read_json(ROOT / "evals/config.example.json"))

    def test_prepare_refuses_existing_evidence(self):
        with self.assertRaisesRegex(ab.EvalError, "already exists"):
            ab.prepare(self.root, self.run, config(), "pilot")

    def test_pilot_has_exactly_three_repetitions(self):
        altered = config()
        altered["repetitions"] = 4
        with self.assertRaisesRegex(ab.EvalError, "exactly 3"):
            ab.prepare(self.root, self.base / "new", altered, "pilot")

    def test_frozen_integrity_checks(self):
        ab.write_json(self.run / "private/skill.json", {"SKILL.md": "tampered"})
        with self.assertRaisesRegex(ab.EvalError, "skill snapshot"):
            ab.load_manifest(self.run)

    def test_generation_pair_settings_and_workspace_isolation(self):
        seen = []
        def adapter(_command, request, cwd, _timeout):
            seen.append(copy.deepcopy(request))
            self.assertEqual(Path(request["project_dir"]), cwd)
            if request["skill_dir"]:
                self.assertTrue((Path(request["skill_dir"]) / "SKILL.md").exists())
            else:
                self.assertFalse((cwd.parent / "skill").exists())
            self.assertNotIn("must", request)
            self.assertNotIn("rubric", request)
            self.assertNotIn("case_id", request)
            return response(request)
        with patch.object(ab, "call_adapter", side_effect=adapter):
            self.assertEqual(ab.generate(self.run, "fixture", limit=2), 2)
        self.assertEqual(seen[0]["model"], seen[1]["model"])
        self.assertEqual(seen[0]["seed"], seen[1]["seed"])
        self.assertEqual(seen[0]["tool_policy"], seen[1]["tool_policy"])
        self.assertNotEqual(seen[0]["project_dir"], seen[1]["project_dir"])

    def test_judge_is_blind_and_order_swapped(self):
        seen = []
        def adapter(_command, request, _cwd, _timeout):
            seen.append(copy.deepcopy(request))
            return response(request)
        with patch.object(ab, "call_adapter", side_effect=adapter):
            ab.generate(self.run, "fixture", limit=2)
            ab.judge(self.run, "fixture", limit=2)
        one, two = seen[2:]
        self.assertEqual(one["candidates"]["X"], two["candidates"]["Y"])
        self.assertEqual(one["candidates"]["Y"], two["candidates"]["X"])
        for packet in (one, two):
            self.assertNotIn("condition", json.dumps(packet))
            self.assertNotIn("test-generator", json.dumps(packet))
            self.assertNotIn("T-00", json.dumps(packet))
            self.assertNotIn("refs", packet["case"])
            self.assertNotIn("skill_dir", packet)

    def test_resume_does_not_repeat_calls(self):
        self.fill()
        with patch.object(ab, "call_adapter", side_effect=AssertionError("must not rerun")):
            self.assertEqual(ab.generate(self.run, "fixture"), 0)
            self.assertEqual(ab.judge(self.run, "fixture"), 0)

    def test_missing_answer_prevents_partial_mean(self):
        self.fill()
        next((self.run / "private/answers").glob("*.json")).unlink()
        result = ab.report(self.run, root=self.root)
        self.assertEqual(result["status"], "PENDING")
        self.assertIsNone(result["overall"])
        self.assertEqual(result["categories"], {})

    def test_synthetic_never_passes_release(self):
        self.fill()
        result = ab.report(self.run, root=self.root)
        self.assertEqual(result["status"], "SYNTHETIC")
        self.assertEqual(result["release_gate"], "BLOCKED")
        self.assertEqual(result["overall"]["task_bootstrap_95ci"], [1, 1])
        self.assertEqual(result["overall"]["paired_repetitions"], 90)
        with self.assertRaisesRegex(ab.EvalError, "synthetic"):
            ab.prepare(self.root, self.base / "full", config(), "full", self.run)

    def test_full_requires_passing_pilot_and_preserves_metadata(self):
        # "external" is exercised only as protocol test data in a temporary directory.
        self.fill(source="external")
        result = ab.report(self.run, root=self.root)
        self.assertEqual(result["release_gate"], "PASS")
        self.assertTrue(all(result["release_criteria"].values()))
        self.assertEqual(result["categories"]["test"]["metadata"]["generator"], config()["generator"])
        full = ab.prepare(self.root, self.base / "full", config(), "full", self.run)
        self.assertIsNotNone(full["pilot_evidence"])
        self.assertEqual(full["phase"], "full")
        self.assertTrue((self.base / "full/private/pilot/private/answers/T-00--1--skill.json").exists())
        self.assertTrue(ab.report(self.base / "full", root=self.root)["pilot_verified"])
        altered = config()
        altered["generator"]["settings"]["temperature"] = .9
        with self.assertRaisesRegex(ab.EvalError, "differs"):
            ab.prepare(self.root, self.base / "other", altered, "full", self.run)

    def test_hard_gate_in_either_order_vetoes_case(self):
        def custom(request, value):
            if request["operation"] == "judge":
                for label, c in request["candidates"].items():
                    if c["answer"] == "better" and label == "X":
                        value["grades"][label] = grade(3, "money_duplication")
            return value
        self.fill(source="external", custom=custom)
        result = ab.report(self.run, root=self.root)
        self.assertEqual(result["hard_gate_status"], "BLOCKED")
        self.assertEqual(result["release_gate"], "BLOCKED")
        self.assertEqual(result["overall"]["skill_mean"], 0)
        self.assertEqual(result["overall"]["hard_gate_failure_pairs"]["skill"]["money_duplication"], 90)

    def test_security_dimension_regression_blocks_release_despite_completion_gain(self):
        def custom(request, value):
            if request["operation"] == "judge":
                for label, candidate in request["candidates"].items():
                    value["grades"][label]["scores"]["security_authority"] = 0 if candidate["answer"] == "better" else 3
            return value
        self.fill(source="external", custom=custom)
        result = ab.report(self.run, root=self.root)
        self.assertTrue(result["release_criteria"]["positive_overall_ci"])
        self.assertFalse(result["release_criteria"]["no_security_honesty_regression"])
        self.assertEqual(result["overall"]["rubric_safety_dimensions"]["security_authority"]["task_bootstrap_95ci"], [-3, -3])
        self.assertEqual(result["release_gate"], "BLOCKED")

    def test_uncertain_gate_requires_review(self):
        def custom(request, value):
            if request["operation"] == "judge":
                for label, c in request["candidates"].items():
                    if c["answer"] == "better":
                        value["grades"][label]["hard_gates"]["plugin_only_writes"] = {
                            "violated": False, "uncertain": True, "evidence": "Fixture ambiguity"}
            return value
        self.fill(source="external", custom=custom)
        self.assertEqual(ab.report(self.run, root=self.root)["hard_gate_status"], "NEEDS_REVIEW")

    def test_high_rubric_score_cannot_replace_verified_completion(self):
        def custom(request, value):
            if request["operation"] == "judge":
                for label, c in request["candidates"].items():
                    if c["answer"] == "better":
                        value["grades"][label]["task_completed"] = False
            return value
        self.fill(source="external", custom=custom)
        result = ab.report(self.run, root=self.root)
        self.assertEqual(result["overall"]["skill_mean"], 0)
        self.assertEqual(result["overall"]["rubric_secondary"]["skill_mean"], 3)
        self.assertFalse(result["release_criteria"]["positive_overall_ci"])

    def test_both_judge_orders_must_verify_completion(self):
        def custom(request, value):
            if request["operation"] == "judge":
                for label, c in request["candidates"].items():
                    if c["answer"] == "better" and label == "X":
                        value["grades"][label]["completion_verifiable"] = False
            return value
        self.fill(source="external", custom=custom)
        result = ab.report(self.run, root=self.root)
        self.assertEqual(result["overall"]["skill_mean"], 0)
        self.assertEqual(result["overall"]["order_disagreement_pairs"], 90)

    def test_zero_baseline_fabrications_cannot_claim_reduction(self):
        def custom(request, value):
            if request["operation"] == "judge":
                value["grades"] = {label: grade(3 if c["answer"] == "better" else 1)
                                   for label, c in request["candidates"].items()}
            return value
        self.fill(source="external", custom=custom)
        result = ab.report(self.run, root=self.root)
        self.assertFalse(result["release_criteria"]["fewer_fabricated_test_claims"])
        self.assertEqual(result["release_gate"], "BLOCKED")

    def test_changed_answer_after_judging_is_rejected(self):
        self.fill()
        path = next((self.run / "private/answers").glob("*.json"))
        answer = ab.read_json(path)
        answer["response"]["answer"] = "tampered"
        ab.write_json(path, answer)
        with self.assertRaisesRegex(ab.EvalError, "answers changed"):
            ab.report(self.run, root=self.root)

    def test_effective_settings_mismatch_is_rejected(self):
        request = {"operation": "generate", "model": config()["generator"], "seed": 1, "skill_dir": None}
        result = response(request)
        result["effective"]["seed"] = 2
        with self.assertRaisesRegex(ab.EvalError, "differ"):
            ab.check_response(result, request["model"], 1)


class PureFunctions(unittest.TestCase):
    def test_bootstrap_task_clusters_and_repeatability(self):
        a = ab.bootstrap([-1, 2, 3], 10, 1000)
        self.assertEqual(a, ab.bootstrap([-1, 2, 3], 10, 1000))
        self.assertEqual(ab.bootstrap([2], 10, 1000), [2, 2])
        self.assertGreaterEqual(a[0], -1)
        self.assertLessEqual(a[1], 3)

    def test_state_checks_read_files_not_answer_prose(self):
        case = {"initial_files": {"a.luau": "BAD"}, "state_checks": [
            {"name": "patch", "path": "a.luau", "op": "absent", "pattern": "BAD"},
            {"name": "preserve", "path": "proof.json", "op": "unchanged"}]}
        self.assertFalse(ab.state_checks(case, {"a.luau": "BAD"})[0]["passed"])
        self.assertFalse(ab.state_checks(case, {})[0]["passed"])
        self.assertTrue(ab.state_checks(case, {"a.luau": "FIXED"})[0]["passed"])

    def test_negative_trigger_requires_zero_skill_access(self):
        case = {"kind": "negative-trigger"}
        response_value = {"skill_audit": {"collector": "adapter_tool_boundary", "complete": True,
                                         "events": [{"operation": "read", "path": "SKILL.md"}]}}
        self.assertFalse(ab.routing_valid(case, {"response": response_value}))
        response_value["skill_audit"]["events"] = []
        self.assertTrue(ab.routing_valid(case, {"response": response_value}))
        del response_value["skill_audit"]["complete"]
        with self.assertRaises(ab.EvalError):
            ab.validate_skill_audit(response_value, "skill")

    def test_grade_requires_all_gates_and_bounded_integer_scores(self):
        good = grade()
        ab.validate_grade(good)
        del good["hard_gates"]["money_duplication"]
        with self.assertRaises(ab.EvalError):
            ab.validate_grade(good)
        good = grade()
        good["scores"]["correctness"] = True
        with self.assertRaises(ab.EvalError):
            ab.validate_grade(good)

    def test_rejects_path_traversal_and_symlink_artifacts(self):
        for path in ("../secret", "/secret", "x/../../secret", "x\\y"):
            with self.assertRaises(ab.EvalError):
                ab.relative_path(path)
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "link").symlink_to("/tmp")
            with self.assertRaisesRegex(ab.EvalError, "symlink"):
                ab.collect_files(root)

    def test_explicit_translation_output_language_is_respected(self):
        sys.path.insert(0, str(ROOT / "evals"))
        import grade as pregrade
        case = {"id": "TRANSLATE", "category": "negative-triggers", "lang": "ru", "answer_lang": "en"}
        self.assertEqual(pregrade.grade(case, "I play Roblox after work.")["auto"], "PASS-AUTO")

    def test_real_adapter_subprocess_json_contract(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            script = root / "adapter.py"
            script.write_text('import json,sys\nx=json.load(sys.stdin)\nprint(json.dumps({"echo":x["message"]}))\n')
            value = ab.call_adapter(f'{sys.executable} "{script}"', {"message": "hello"}, root, 10)
            self.assertEqual(value, {"echo": "hello"})

    def test_repository_case_coverage(self):
        cases = ab.load_cases()
        pilot = json.loads((ROOT / "evals/pilot.json").read_text())
        self.assertEqual(len(pilot), 40)
        self.assertEqual(len(cases), len({c["id"] for c in cases}))
        categories = {c["category"] for c in cases}
        selected = [c for c in cases if c["id"] in pilot]
        self.assertEqual(categories, {c["category"] for c in selected})
        self.assertEqual(categories, {c["category"] for c in selected if c["lang"] == "ru"})
        self.assertEqual(sum(c["kind"] == "agentic" for c in selected), 4)
        self.assertEqual(sum(c["kind"] == "negative-trigger" for c in selected), 4)
        self.assertTrue(all(any(not r["passed"] for r in ab.state_checks(c, c["initial_files"]))
                            for c in cases if c["kind"] == "agentic"))
        snapshot = ab.snapshot_skill(ROOT)
        self.assertNotIn("tools/run_ab.py", snapshot)
        self.assertFalse(any(p.startswith("evals/") for p in snapshot))


if __name__ == "__main__":
    unittest.main()
