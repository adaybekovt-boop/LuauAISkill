"""Unit tests for the repository tools and data files. Run: python -m unittest discover -s tests
Pure Python, no network, no Luau toolchain needed (the committed api/ index is used)."""
from __future__ import annotations

import json
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "evals"))

import api  # noqa: E402
import check_api_refs  # noqa: E402
import check_links  # noqa: E402
import embed_code  # noqa: E402
import render_legacy  # noqa: E402
import scan_legacy  # noqa: E402


def refs(text: str, code: bool = True, legacy: bool = False, fake: bool = False, shadow=frozenset()) -> list:
    return check_api_refs.check_line(text, legacy, fake, code, check_api_refs.restricted_props(),
                                     check_api_refs.datatype_owners(), shadow)


class ApiIndex(unittest.TestCase):
    def test_counts_are_plausible(self):
        self.assertGreater(len(api.classes()), 800)
        self.assertGreater(sum(len(m) for m in api.members().values()), 7000)

    def test_inheritance_resolution(self):
        owner, row = api.resolve_member("Part", "Anchored")
        self.assertEqual(owner, "BasePart")
        self.assertEqual(row["kind"], "Property")

    def test_studio_only_properties(self):
        _, style = api.resolve_member("Lighting", "LightingStyle")
        self.assertIn("write:plugin-only", style["flags"])
        _, tech = api.resolve_member("Lighting", "Technology")
        self.assertNotEqual(tech["write"], "None")

    def test_deprecations_and_undocumented(self):
        _, load = api.resolve_member("Humanoid", "LoadAnimation")
        self.assertIn("deprecated", load["flags"])
        self.assertIn("undocumented", api.classes()["PlayerDataService"]["tags"])

    def test_enums(self):
        self.assertIn("Exclude", api.enums()["RaycastFilterType"])
        self.assertNotIn("Blacklist", api.enums()["RaycastFilterType"])

    def test_missing_member(self):
        self.assertIsNone(api.resolve_member("Lighting", "GlobalIllumination"))


class ApiRefChecker(unittest.TestCase):
    def test_flags_hallucinated_member(self):
        self.assertTrue(any(sev == "error" for sev, _ in refs("Lighting.GlobalIllumination = true")))

    def test_flags_removed_enum_item(self):
        self.assertTrue(any("Blacklist" in m for _, m in refs("p.FilterType = Enum.RaycastFilterType.Blacklist")))

    def test_flags_deprecated_global_in_code_only(self):
        self.assertTrue(any("wait()" in m for _, m in refs("wait(1)")))
        self.assertFalse(refs("task.wait(1)"))

    def test_fake_marker_and_legacy_context(self):
        self.assertFalse(refs("Lighting.GlobalIllumination -- FAKE", fake=True))
        self.assertFalse(refs("humanoid:LoadAnimation(a)", legacy=True))

    def test_restricted_write(self):
        self.assertTrue(any("LightingStyle" in m for _, m in refs("Lighting.LightingStyle = x")))

    def test_shadowed_class_name_is_not_engine_class(self):
        self.assertFalse(refs("Noise.emit(n, pos, 1, now)", shadow=frozenset({"Noise"})))
        self.assertTrue(refs("Noise.emit(n, pos, 1, now)"))


class Links(unittest.TestCase):
    def test_github_slugs(self):
        self.assertEqual(check_links.slug("Graphics (`recipes/graphics/`)"), "graphics-recipesgraphics")
        self.assertEqual(check_links.slug("Ragdoll (on death or knock-down)"), "ragdoll-on-death-or-knock-down")
        self.assertEqual(check_links.slug("1. Hallucinated APIs (they sound plausible, they don't exist)"),
                         "1-hallucinated-apis-they-sound-plausible-they-dont-exist")

    def test_repository_links_are_valid(self):
        res = subprocess.run([sys.executable, "tools/check_links.py"], cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, res.stdout[-800:])


class Embeds(unittest.TestCase):
    def test_region_extraction(self):
        text = embed_code.extract("examples/lighting/ReplicatedStorage/LightingPresets.luau#Sunset")
        self.assertIn("Presets.Sunset", text)
        self.assertNotIn("Presets.FogDay", text)

    def test_embeds_are_current(self):
        res = subprocess.run([sys.executable, "tools/embed_code.py", "--check"], cwd=ROOT, capture_output=True,
                             text=True)
        self.assertEqual(res.returncode, 0, res.stdout)


class LegacyCatalog(unittest.TestCase):
    def test_catalog_valid_and_rendered(self):
        data = json.loads((ROOT / "references/legacy-modernization/catalog.json").read_text(encoding="utf-8"))
        self.assertEqual(render_legacy.validate(data), [])
        rendered = (ROOT / "references/legacy-modernization/CATALOG.md").read_text(encoding="utf-8")
        self.assertEqual(render_legacy.render(data), rendered)

    def test_scanner_rules_find_legacy_code(self):
        rules = scan_legacy.load_rules(use_api=False)
        sample = (ROOT / "evals/fixtures/legacy-grab-bag.luau").read_text(encoding="utf-8")
        hits = {rid for rid, rx, _ in rules if rx.search(sample)}
        for expected in ("anim-humanoid-load", "sched-spawn", "query-findpartonray", "phys-bodymovers", "async-group"):
            self.assertIn(expected, hits)


class LightingPresets(unittest.TestCase):
    SECTION_CLASS = {"lighting": "Lighting", "atmosphere": "Atmosphere", "colorCorrection": "ColorCorrectionEffect",
                     "bloom": "BloomEffect", "sunRays": "SunRaysEffect"}

    def test_every_preset_key_is_a_writable_property(self):
        src = (ROOT / "examples/lighting/ReplicatedStorage/LightingPresets.luau").read_text(encoding="utf-8")
        checked = 0
        for m in re.finditer(r"(\w+) = \{([^{}]*)\}", src):
            cls = self.SECTION_CLASS.get(m.group(1))
            if not cls:
                continue
            for key in re.findall(r"(\w+) =", m.group(2)):
                found = api.resolve_member(cls, key)
                self.assertIsNotNone(found, f"{cls}.{key}")
                _, row = found
                self.assertEqual(row["write"], "None", f"{cls}.{key}")
                self.assertNotIn("plugin-only", row["flags"], f"{cls}.{key}")
                self.assertNotIn("readonly", row["flags"], f"{cls}.{key}")
                checked += 1
        self.assertGreater(checked, 80)


class Evals(unittest.TestCase):
    def test_cases_are_well_formed(self):
        ids = set()
        for f in sorted((ROOT / "evals/cases").glob("*.jsonl")):
            for line in f.read_text(encoding="utf-8").splitlines():
                c = json.loads(line)
                self.assertEqual(c["category"], f.stem, c["id"])
                self.assertNotIn(c["id"], ids)
                ids.add(c["id"])
                for key in ("prompt", "must", "must_not", "critical", "refs", "kind", "lang"):
                    self.assertIn(key, c, c["id"])
                if "fixture" in c:
                    self.assertTrue((ROOT / c["fixture"]).exists(), c["fixture"])
                for rx in c.get("auto", {}).get("forbid", []) + c.get("auto", {}).get("require_any", []):
                    re.compile(rx)
                for ref in c["refs"]:
                    self.assertTrue((ROOT / ref).exists(), f"{c['id']}: {ref}")
        self.assertGreaterEqual(len(ids), 120)

    def test_grader_flags_hallucinations(self):
        import grade  # noqa: PLC0415
        case = {"id": "T", "category": "t", "auto": {"forbid": [r"Blacklist"]}, "lang": "en"}
        bad = grade.grade(case, "```luau\nLighting.GlobalIllumination = true\nx = Enum.RaycastFilterType.Blacklist\n```")
        self.assertEqual(bad["auto"], "FLAGGED")
        good = grade.grade(case, "Blacklist was removed.\n```luau\nlocal p = RaycastParams.new()\n```")
        self.assertEqual(good["auto"], "PASS-AUTO")


class Search(unittest.TestCase):
    def test_finds_save_system_for_session_locking(self):
        res = subprocess.run([sys.executable, "tools/search.py", "session locking", "-n", "5"], cwd=ROOT,
                             capture_output=True, text=True)
        self.assertEqual(res.returncode, 0)
        self.assertIn("save-system.md", res.stdout)


class SourcePins(unittest.TestCase):
    def test_lock_and_toolchain_files(self):
        lock = json.loads((ROOT / "sources/lock.json").read_text(encoding="utf-8"))
        text = json.dumps(lock)
        self.assertRegex(text, r"[0-9a-f]{40}")
        json.loads((ROOT / "sources/toolchain.json").read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
