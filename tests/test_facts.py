"""Facts schema/render/source/expiry regression tests. No network or upstream corpus required."""
from __future__ import annotations

import copy
import datetime as dt
import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import check_facts  # noqa: E402
import render_facts  # noqa: E402

TODAY = dt.date(2026, 10, 2)


def sample():
    return {"schema_version": 1, "source_pins": {"creator-docs": "a" * 40}, "facts": [{
        "id": "test-limit", "section": "Testing", "statement": "Example maximum.", "value": 10,
        "unit": "items", "status": "documented", "source": "cd:example", "checked_on": "2026-10-02",
        "expires_after": 30, "evidence": ["The maximum is 10 items."],
    }]}


class FactSchema(unittest.TestCase):
    def test_valid_data(self):
        self.assertEqual(check_facts.validate(sample(), as_of=TODAY), [])

    def test_missing_required_fields(self):
        for field in check_facts.REQUIRED:
            with self.subTest(field=field):
                data = sample()
                del data["facts"][0][field]
                self.assertTrue(check_facts.validate(data, as_of=TODAY))

    def test_duplicate_and_invalid_ids(self):
        data = sample()
        data["facts"].append(copy.deepcopy(data["facts"][0]))
        self.assertIn("test-limit: duplicate id", check_facts.validate(data, as_of=TODAY))
        data["facts"][0]["id"] = "Not An ID"
        self.assertTrue(any("invalid id" in e for e in check_facts.validate(data, as_of=TODAY)))

    def test_malformed_inputs_report_errors_not_tracebacks(self):
        for data in ([], None, {}, {"schema_version": 1, "facts": [None]},
                     {"schema_version": 1, "facts": [{"id": []}]}):
            with self.subTest(data=data):
                self.assertTrue(check_facts.validate(data, as_of=TODAY))

    def test_unknown_status(self):
        data = sample()
        data["facts"][0]["status"] = "probably-shipped"
        self.assertTrue(any("unknown status" in e for e in check_facts.validate(data, as_of=TODAY)))

    def test_release_status_needs_explicit_evidence(self):
        data = sample()
        data["facts"][0]["status"] = "ga"
        self.assertTrue(any("explicit status evidence" in e for e in check_facts.validate(data, as_of=TODAY)))
        data["facts"][0]["evidence"] = ["[Full Release] Feature announcement"]
        self.assertEqual(check_facts.validate(data, as_of=TODAY), [])

    def test_expiry_boundary_is_inclusive(self):
        self.assertEqual(check_facts.validate(sample(), as_of=TODAY + dt.timedelta(days=29)), [])
        errors = check_facts.validate(sample(), as_of=TODAY + dt.timedelta(days=30))
        self.assertIn("test-limit: expired on 2026-11-01; reverify source", errors)

    def test_future_checked_date_rejected(self):
        self.assertTrue(any("future" in e for e in check_facts.validate(sample(), as_of=TODAY - dt.timedelta(days=1))))

    def test_invalid_dates_and_lifetimes(self):
        for value in ("2026-02-30", "20261002", 20261002, "today", "9999-12-31", None):
            data = sample()
            data["facts"][0]["checked_on"] = value
            self.assertTrue(check_facts.validate(data, as_of=TODAY))
        for value in (True, 0, -1, 367, "30", 1.5, None):
            data = sample()
            data["facts"][0]["expires_after"] = value
            self.assertTrue(check_facts.validate(data, as_of=TODAY))

    def test_nonfinite_empty_values_rejected(self):
        for value in (float("nan"), float("inf"), None, [], {}, "", [None]):
            data = sample()
            data["facts"][0]["value"] = value
            self.assertTrue(check_facts.validate(data, as_of=TODAY))

    def test_duplicate_json_keys_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "bad.json"
            path.write_text('{"facts": [], "facts": [1]}')
            with self.assertRaisesRegex(ValueError, "duplicate JSON key"):
                check_facts.load_json(path)

    def test_invalid_json_numbers_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "bad.json"
            path.write_text('{"value": NaN}')
            with self.assertRaisesRegex(ValueError, "invalid JSON number"):
                check_facts.load_json(path)


class PinnedSources(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.root = Path(cls.temp.name)
        pins = {}
        payloads = {
            "creator-docs": {"content/en-us/example.md": "The maximum is\n  10 items.\n",
                             "content/en-us/reference/cloud/openapi.json": '{"description":"Maximum 4 MB.\\nNext line."}'},
            "api-dump": {"Full-API-Dump.json": json.dumps({"Classes": [
                {"Name": "Parent", "Superclass": "<<<ROOT>>>", "Members": [
                    {"Name": "Test", "Security": "PluginSecurity", "MemberType": "Function"}]},
                {"Name": "Child", "Superclass": "Parent", "Members": []}],
                "Enums": [{"Name": "TestEnum", "Items": [{"Name": "First", "Value": 0}]}]})},
        }
        for name, files in payloads.items():
            repo = cls.root / ".cache" / "sources" / name
            repo.mkdir(parents=True)
            for filename, body in files.items():
                path = repo / filename
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(body, encoding="utf-8")
            for command in (["git", "init", "-q"], ["git", "add", "."],
                            ["git", "-c", "user.name=Facts tests", "-c", "user.email=test@example.invalid",
                             "commit", "-qm", "fixture"]):
                subprocess.run(command, cwd=repo, check=True, capture_output=True)
            sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
            owner = "Roblox/creator-docs" if name == "creator-docs" else "MaximumADHD/Roblox-Client-Tracker"
            pins[name] = {"sha": sha, "url": f"https://github.com/{owner}.git"}
        (cls.root / "sources").mkdir()
        (cls.root / "sources/lock.json").write_text(json.dumps({"sources": pins}))
        cls.pins = pins

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def data(self):
        data = sample()
        data["source_pins"] = {key: value["sha"] for key, value in self.pins.items()}
        return data

    def test_document_and_evidence_resolve(self):
        self.assertEqual(check_facts.validate(self.data(), as_of=TODAY,
                         resolver=check_facts.SourceResolver(self.root)), [])

    def test_changed_source_pin_fails(self):
        data = self.data()
        data["source_pins"]["creator-docs"] = "f" * 40
        errors = check_facts.validate(data, as_of=TODAY, resolver=check_facts.SourceResolver(self.root))
        self.assertTrue(any("source pin changed" in e for e in errors))

    def test_missing_document_fails(self):
        with self.assertRaisesRegex(ValueError, "unresolved document"):
            check_facts.SourceResolver(self.root).resolve("cd:does-not-exist")

    def test_incorrect_evidence_fails(self):
        data = self.data()
        data["facts"][0]["evidence"] = ["The maximum is 5000 items."]
        errors = check_facts.validate(data, as_of=TODAY, resolver=check_facts.SourceResolver(self.root))
        self.assertTrue(any("evidence not found" in e for e in errors))

    def test_worktree_edits_are_not_evidence(self):
        path = self.root / ".cache/sources/creator-docs/content/en-us/example.md"
        original = path.read_text()
        try:
            path.write_text("The maximum is 5000 items.")
            resolved = check_facts.SourceResolver(self.root).resolve("cd:example")
            self.assertIn("10 items", resolved.text)
            self.assertNotIn("5000", resolved.text)
        finally:
            path.write_text(original)

    def test_source_paths_cannot_escape(self):
        resolver = check_facts.SourceResolver(self.root)
        for source in ("cd:../secret", "cd:/secret", "cd:example/../../secret", "cd:example//secret"):
            with self.subTest(source=source), self.assertRaises(ValueError):
                resolver.resolve(source)

    def test_api_members_inherit_and_enum_items_resolve(self):
        resolver = check_facts.SourceResolver(self.root)
        self.assertIn("PluginSecurity", resolver.resolve("api:Child.Test").text)
        self.assertIn('"Value": 0', resolver.resolve("api:Enum.TestEnum.First").text)
        for ref in ("api:Child.Fake", "api:Child.Test.Extra", "api:Enum.TestEnum.Fake", "api:Fake"):
            with self.subTest(ref=ref), self.assertRaises(ValueError):
                resolver.resolve(ref)

    def test_live_document_url_maps_to_pin(self):
        resolver = check_facts.SourceResolver(self.root)
        source = resolver.resolve("https://create.roblox.com/docs/example")
        self.assertIn(self.pins["creator-docs"]["sha"], source.url)

    def test_blob_url_requires_exact_pin(self):
        resolver = check_facts.SourceResolver(self.root)
        base = "https://github.com/Roblox/creator-docs/blob/"
        source = resolver.resolve(base + self.pins["creator-docs"]["sha"] + "/content/en-us/example.md")
        self.assertIn("10 items", source.text)
        with self.assertRaises(ValueError):
            resolver.resolve(base + "main/content/en-us/example.md")

    def test_pinned_json_url_decodes_line_breaks(self):
        resolver = check_facts.SourceResolver(self.root)
        source = resolver.resolve("https://github.com/Roblox/creator-docs/blob/" +
                                  self.pins["creator-docs"]["sha"] + "/content/en-us/reference/cloud/openapi.json")
        self.assertIn("Maximum 4 MB.\nNext line.", source.text)

    def test_unregistered_live_url_fails(self):
        with self.assertRaisesRegex(ValueError, "pinned corpus"):
            check_facts.SourceResolver(self.root).resolve("https://example.com/unsupported")

    def test_missing_corpus_fails(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "sources").mkdir()
            (root / "sources/lock.json").write_text(json.dumps({"sources": self.pins}))
            with self.assertRaisesRegex(ValueError, "corpus missing"):
                check_facts.SourceResolver(root).resolve("cd:example")

    def test_url_snapshot_hash_and_source_checked(self):
        url = "https://devforum.roblox.com/t/test-announcement/123"
        path = self.root / "references/fact-sources/announcement.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({"source": url, "published_on": "2026-09-01", "retrieved_on": "2026-10-02",
                                    "excerpt": "[Full Release] A feature."}))
        spec = {url: {"file": "references/fact-sources/announcement.json",
                      "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}}
        self.assertIn("Full Release", check_facts.SourceResolver(self.root, spec).resolve(url).text)
        path.write_text("changed")
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            check_facts.SourceResolver(self.root, spec).resolve(url)
        path.unlink()
        with self.assertRaises(OSError):
            check_facts.SourceResolver(self.root, spec).resolve(url)


class FactsRendering(unittest.TestCase):
    def test_table_is_deterministic_and_contains_dates(self):
        rendered = render_facts.render(sample())
        self.assertEqual(rendered, render_facts.render(sample()))
        self.assertIn("2026-10-02 / 2026-11-01", rendered)
        self.assertIn("`test-limit`", rendered)

    def test_pipe_and_newline_escaping(self):
        self.assertEqual(render_facts.cell("first|second\nthird"), "first&#124;second third")

    def test_committed_facts_are_well_formed_at_review_date(self):
        data = check_facts.load_json(ROOT / "references/facts.json")
        # Historical structural regression: CLI owns current-day expiry checking.
        self.assertEqual(check_facts.validate(data, as_of=TODAY), [])
        self.assertGreaterEqual(len(data["facts"]), 80)

    def test_committed_table_matches_json(self):
        data = check_facts.load_json(ROOT / "references/facts.json")
        self.assertEqual(render_facts.render(data), (ROOT / "references/limits.md").read_text(encoding="utf-8"))

    def test_server_authority_release_regression(self):
        data = check_facts.load_json(ROOT / "references/facts.json")
        indexed = {fact["id"]: fact for fact in data["facts"]}
        self.assertEqual(indexed["server-authority-release-status"]["status"], "ga")
        self.assertEqual(indexed["server-authority-release-date"]["value"], "2026-07-09")
        self.assertIn("4727993", indexed["server-authority-release-status"]["source"])
        self.assertEqual(indexed["batch-get-max-keys"]["status"], "default")


if __name__ == "__main__":
    unittest.main()
