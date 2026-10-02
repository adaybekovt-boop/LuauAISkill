"""Synthetic in-memory/tmp fixtures test the checker; these are NEVER engine execution evidence."""
from __future__ import annotations

import copy
import datetime as dt
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import check_engine_evidence as gate


class EngineEvidence(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.manifest = gate.read_json(gate.MANIFEST)
        for case in self.manifest["cases"]:
            case.update(status="NOT RUN", blocker="synthetic test fixture: no engine invoked", receipts=[])
        self.case = copy.deepcopy(next(c for c in self.manifest["cases"] if c["id"] == "inventory"))
        self.digest = gate.source_digest(self.case)
        self.result = self.result_for(self.case)
        self.receipt = self.receipt_for(self.result)

    def result_for(self, case):
        end = dt.datetime.now(dt.timezone.utc)
        return {
            "schema_version": 1, "case": case["id"], "run_id": str(uuid.uuid4()),
            "source_digest": gate.source_digest(case), "started_at": (end - dt.timedelta(seconds=2)).isoformat(),
            "finished_at": end.isoformat(), "environment": "studio-server-clients", "engine_version": "0.741.19.7411056",
            "universe_id": 0, "place_id": 0, "place_version": 0, "client_count": case["minimum_clients"],
            "status": "PASS", "assertions": [{"id": name, "status": "PASS", "detail": "synthetic unit-test data"}
                                              for name in case["assertions"]],
        }

    def file(self, name, value, raw=False):
        path = self.base / name
        path.write_text(value if raw else json.dumps(value), encoding="utf-8")
        return {"path": name, "sha256": gate.sha256(path)}

    def receipt_for(self, result):
        return {"schema_version": 1, "label": "STUDIO TESTED",
                "result": self.file("result.json", result),
                "capture": self.file("console.txt", "[server] " + gate.MARKER + json.dumps(result) + "\n", True),
                "runner": {"environment": result["environment"], "id": "synthetic-session-only",
                           "mode": "Server & Clients", "clients": result["client_count"],
                           "engine_version": result["engine_version"]}, "screenshots": {}}

    def check(self, result=None, receipt=None, case=None):
        if result is not None:
            receipt = self.receipt_for(result)
        return gate.validate_receipt(receipt or self.receipt, case or self.case, self.base,
                                     gate.source_digest(case or self.case))

    def test_pending_infrastructure_is_valid_but_not_release_evidence(self):
        errors, pending = gate.validate_manifest(self.manifest, evidence_base=self.base, allow_pending=True)
        self.assertEqual(errors, [])
        self.assertEqual(set(pending), set(gate.REQUIRED))
        errors, pending = gate.validate_manifest(self.manifest, evidence_base=self.base)
        self.assertEqual(len(errors), 10)
        self.assertEqual(len(pending), 10)

    def test_synthetic_complete_receipt_validates_only_in_temporary_fixture(self):
        self.assertEqual(self.check(), self.result["run_id"])

    def test_missing_case_rejected(self):
        self.manifest["cases"].pop()
        self.assertTrue(gate.validate_manifest(self.manifest, allow_pending=True)[0])

    def test_duplicate_case_rejected(self):
        self.manifest["cases"].append(self.manifest["cases"][0])
        self.assertTrue(gate.validate_manifest(self.manifest, allow_pending=True)[0])

    def test_pending_cannot_carry_a_receipt(self):
        self.manifest["cases"][0]["receipts"] = [{"path": "pretend.json"}]
        self.assertTrue(gate.validate_manifest(self.manifest, allow_pending=True)[0])

    def test_executed_claim_without_receipt_rejected(self):
        self.manifest["cases"][0].update(status="STUDIO TESTED", blocker="")
        self.assertTrue(gate.validate_manifest(self.manifest, allow_pending=True)[0])

    def test_pending_needs_exact_blocker(self):
        self.manifest["cases"][0]["blocker"] = ""
        self.assertTrue(gate.validate_manifest(self.manifest, allow_pending=True)[0])

    def test_manifest_cannot_weaken_checks(self):
        for field, value in (("assertions", []), ("minimum_clients", -1), ("source_roots", []),
                             ("allowed_environments", ["CLI-EXECUTED"])):
            with self.subTest(field=field):
                manifest = copy.deepcopy(self.manifest)
                manifest["cases"][0][field] = value
                self.assertTrue(gate.validate_manifest(manifest, allow_pending=True)[0])

    def test_bad_result_fields_fail_closed(self):
        changes = {"status": "NOT RUN", "source_digest": "0" * 64, "environment": "open-cloud",
                   "client_count": 1, "engine_version": "unknown", "run_id": "made up", "place_id": True,
                   "assertions": [], "case": "settings-menu", "error": "failure", "schema_version": 99}
        for key, value in changes.items():
            with self.subTest(field=key):
                result = copy.deepcopy(self.result)
                result[key] = value
                with self.assertRaises(gate.EvidenceError): self.check(result=result)

    def test_failed_or_skipped_assertion_rejected(self):
        for status in ("FAIL", "SKIPPED", "TYPECHECKED", "CLI-EXECUTED"):
            result = copy.deepcopy(self.result)
            result["assertions"][0]["status"] = status
            with self.subTest(status=status), self.assertRaises(gate.EvidenceError): self.check(result=result)

    def test_missing_unknown_or_duplicate_assertion_rejected(self):
        for action in ("missing", "unknown", "duplicate"):
            result = copy.deepcopy(self.result)
            if action == "missing": result["assertions"].pop()
            elif action == "unknown": result["assertions"][0]["id"] = "made-up"
            else: result["assertions"].append(result["assertions"][0])
            with self.subTest(action=action), self.assertRaises(gate.EvidenceError): self.check(result=result)

    def test_missing_artifact_rejected(self):
        (self.base / "console.txt").unlink()
        with self.assertRaises(gate.EvidenceError): self.check()

    def test_empty_artifact_rejected(self):
        self.receipt["capture"] = self.file("empty.txt", "", True)
        with self.assertRaises(gate.EvidenceError): self.check()

    def test_tampered_artifact_rejected(self):
        (self.base / "console.txt").write_text("altered")
        with self.assertRaises(gate.EvidenceError): self.check()

    def test_matching_digest_cannot_replace_raw_capture(self):
        self.receipt["capture"] = self.file("console.txt", "typechecking passed\n", True)
        with self.assertRaises(gate.EvidenceError): self.check()

    def test_raw_capture_must_match_extracted_assertions(self):
        changed = copy.deepcopy(self.result)
        changed["assertions"][0]["detail"] = "different"
        self.receipt["capture"] = self.file("console.txt", gate.MARKER + json.dumps(changed), True)
        with self.assertRaises(gate.EvidenceError): self.check()

    def test_cannot_select_old_pass_ahead_of_new_failure(self):
        newer = copy.deepcopy(self.result)
        newer.update(run_id=str(uuid.uuid4()), status="FAIL")
        capture = gate.MARKER + json.dumps(self.result) + "\n" + gate.MARKER + json.dumps(newer)
        self.receipt["capture"] = self.file("console.txt", capture, True)
        with self.assertRaises(gate.EvidenceError): self.check()

    def test_repeated_run_marker_rejected(self):
        capture = (gate.MARKER + json.dumps(self.result) + "\n") * 2
        self.receipt["capture"] = self.file("console.txt", capture, True)
        with self.assertRaises(gate.EvidenceError): self.check()

    def test_result_and_capture_must_be_separate(self):
        self.receipt["capture"] = self.receipt["result"]
        with self.assertRaises(gate.EvidenceError): self.check()

    def test_traversal_absolute_and_symlink_escape_rejected(self):
        for path in ("../secret.json", "/tmp/secret.json", "..\\secret.json"):
            with self.subTest(path=path), self.assertRaises(gate.EvidenceError): gate.within(self.base, path)
        (self.base / "escape").symlink_to(ROOT / "SKILL.md")
        with self.assertRaises(gate.EvidenceError): gate.within(self.base, "escape")

    def test_invalid_and_duplicate_json_rejected(self):
        for text in ('{"x": 1, "x": 2}', '{"x": NaN}', 'not json'):
            with self.subTest(text=text), self.assertRaises(gate.EvidenceError): gate.unique_json(text)

    def test_timestamps_require_actual_timezone_and_order(self):
        for field, value in (("started_at", "2026-01-01T00:00:00"), ("finished_at", "2000-01-01T00:00:00Z"),
                             ("finished_at", "2099-01-01T00:00:00Z")):
            result = copy.deepcopy(self.result)
            result[field] = value
            with self.subTest(field=field, value=value), self.assertRaises(gate.EvidenceError): self.check(result=result)

    def test_runner_must_match_observed_environment_and_peers(self):
        for field, value in (("clients", 1), ("environment", "open-cloud"), ("id", ""), ("mode", "Run"),
                             ("engine_version", "different")):
            receipt = copy.deepcopy(self.receipt)
            receipt["runner"][field] = value
            with self.subTest(field=field), self.assertRaises(gate.EvidenceError): self.check(receipt=receipt)

    def test_lighting_requires_all_per_preset_images(self):
        case = next(c for c in self.manifest["cases"] if c["id"] == "lighting-presets")
        result = self.result_for(case)
        with self.assertRaisesRegex(gate.EvidenceError, "per-preset"):
            self.check(result=result, case=case)

    def test_open_cloud_needs_completed_provider_task_and_matching_output(self):
        case = next(c for c in self.manifest["cases"] if c["id"] == "save-system")
        result = self.result_for(case)
        result.update(environment="open-cloud", universe_id=111, place_id=222, place_version=3)
        receipt = self.receipt_for(result)
        receipt["label"] = "CLOUD EXECUTED"
        runner = receipt["runner"]
        runner.update(id="universes/111/places/222/versions/3/luau-execution-session-tasks/" + str(uuid.uuid4()), place_version=3)
        task = {"path": runner["id"], "state": "COMPLETE", "output": {"results": [result]}}
        receipt["task"] = self.file("task.json", task)
        self.assertEqual(self.check(receipt=receipt, case=case), result["run_id"])
        for state in ("QUEUED", "PROCESSING", "FAILED", "CANCELLED"):
            task["state"] = state
            receipt["task"] = self.file("task.json", task)
            with self.subTest(state=state), self.assertRaises(gate.EvidenceError): self.check(receipt=receipt, case=case)
        task.update(state="COMPLETE", output={"results": []})
        receipt["task"] = self.file("task.json", task)
        with self.assertRaises(gate.EvidenceError): self.check(receipt=receipt, case=case)

    def test_open_cloud_cannot_claim_client_or_unpublished_place(self):
        case = next(c for c in self.manifest["cases"] if c["id"] == "save-system")
        result = self.result_for(case)
        result.update(environment="open-cloud", universe_id=111, place_id=222, place_version=3)
        for field, value in (("client_count", 1), ("place_version", 0), ("universe_id", 0)):
            copy_result = {**result, field: value}
            with self.subTest(field=field), self.assertRaises(gate.EvidenceError):
                gate.validate_result(copy_result, case, gate.source_digest(case))

    def test_project_paths_resolve_and_recipe_scripts_stay_in_server_storage(self):
        for case in self.manifest["cases"]:
            path = ROOT / case["project"]
            project = gate.read_json(path)
            def walk(node):
                for key, value in node.items():
                    if key == "$path": self.assertTrue((path.parent / value).resolve().exists(), value)
                    elif isinstance(value, dict): walk(value)
            walk(project["tree"])
            self.assertFalse(project["tree"]["Workspace"]["$attributes"]["ReleaseSmokeEnabled"])
            for name in project["tree"]["ServerScriptService"]:
                if not name.startswith("$"):
                    self.assertNotIn(name, ("DataServer", "RoundServer", "MovementServer", "SettingsServer", "NpcServer"))

    def test_source_digest_binds_module_bytes_and_project(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for directory in self.case["source_roots"]:
                path = root / directory
                path.mkdir(parents=True)
                (path / "module.luau").write_text("return 1\n")
            project = root / self.case["project"]
            project.parent.mkdir(parents=True)
            project.write_text("{}")
            lock = root / "sources/lock.json"
            lock.parent.mkdir(); lock.write_text("{}")
            before = gate.source_digest(self.case, root)
            (root / self.case["source_roots"][0] / "module.luau").write_text("return 2\n")
            self.assertNotEqual(before, gate.source_digest(self.case, root))
            before = gate.source_digest(self.case, root)
            project.write_text('{"changed":true}')
            self.assertNotEqual(before, gate.source_digest(self.case, root))

    def test_cli_default_is_fail_closed_and_schema_mode_does_not_claim_release(self):
        path = self.base / "manifest.json"
        path.write_text(json.dumps(self.manifest))
        command = [sys.executable, str(ROOT / "tools/check_engine_evidence.py"), "--manifest", str(path)]
        blocked = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(blocked.returncode, 1)
        allowed = subprocess.run(command + ["--allow-pending"], capture_output=True, text=True)
        self.assertEqual(allowed.returncode, 0)
        self.assertIn("release gate remains BLOCKED", allowed.stdout)


if __name__ == "__main__":
    unittest.main()
