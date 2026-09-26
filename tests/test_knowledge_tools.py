from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import check_code_blocks  # noqa: E402
import roblox_api  # noqa: E402


class CodeBlockExtraction(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, text: str) -> Path:
        p = self.root / "doc.md"
        p.write_text(text, encoding="utf-8")
        return p

    def test_fence_kinds(self):
        md = self.write(
            "# t\n```luau\n--!strict\n-- @path ReplicatedStorage/X/Mod\nreturn 1\n```\n"
            "```lua\nfoo()\n```\n```text\nignored\n```\n```luau\n-- @run\nassert(true)\n```\n"
        )
        blocks = check_code_blocks.extract(md)
        self.assertEqual([b.lang for b in blocks], ["luau", "lua", "luau"])
        self.assertEqual(blocks[0].path, "ReplicatedStorage/X/Mod")
        self.assertEqual(blocks[0].start_line, 3)
        self.assertFalse(blocks[0].run)
        self.assertTrue(blocks[2].run)

    def test_path_directive_ignored_in_lua_fence(self):
        md = self.write("```lua\n-- @path ReplicatedStorage/Y\n-- @run\n```\n")
        b = check_code_blocks.extract(md)[0]
        self.assertIsNone(b.path)
        self.assertFalse(b.run)

    def test_script_class_from_suffix(self):
        self.assertEqual(check_code_blocks.class_for("Main.server"), ("Main", "Script"))
        self.assertEqual(check_code_blocks.class_for("Input.client"), ("Input", "LocalScript"))
        self.assertEqual(check_code_blocks.class_for("Signal"), ("Signal", "ModuleScript"))

    def test_sourcemap_and_collisions(self):
        md = self.write(
            "```luau\n-- @path ReplicatedStorage/A/Mod\nreturn 1\n```\n"
            "```luau\n-- @path ReplicatedStorage/A/Mod\nreturn 2\n```\n"
            "```luau\n-- @path NotAService/Mod\nreturn 3\n```\n"
        )
        blocks = check_code_blocks.extract(md)
        for n, b in enumerate(blocks):
            b.file = self.root / f"f{n}.luau"
        tree = check_code_blocks.build_sourcemap(blocks, self.root)
        rs = next(c for c in tree["children"] if c["name"] == "ReplicatedStorage")
        folder = next(c for c in rs["children"] if c["name"] == "A")
        self.assertEqual(folder["className"], "Folder")
        self.assertEqual(folder["children"][0]["className"], "ModuleScript")
        self.assertEqual(blocks[0].issues, [])
        self.assertTrue(any("already defined" in i for i in blocks[1].issues))
        self.assertTrue(any("must start with a service" in i for i in blocks[2].issues))

    def test_diagnostic_regex_with_datamodel_suffix(self):
        line = "/tmp/x/src/A.luau [game/ServerScriptService/A](4,1): TypeError: Expected this to be 'string', but got 'number'"
        m = check_code_blocks.DIAG.match(line)
        self.assertIsNotNone(m)
        self.assertEqual(m.group("file"), "/tmp/x/src/A.luau")
        self.assertEqual(m.group("cat"), "TypeError")

    def test_deprecated_api_is_an_error_category(self):
        self.assertIn("DeprecatedApi", check_code_blocks.ERROR_CATEGORIES)


class RobloxApiLookup(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.types, cls.tables, cls.globals, _ = roblox_api.load_defs()

    def test_inheritance_chain(self):
        chain = roblox_api.chain(self.types, "Part")
        self.assertEqual(chain[:3], ["Part", "FormFactorPart", "BasePart"])
        self.assertIn("Instance", chain)

    def test_member_kinds(self):
        humanoid = self.types["Humanoid"].members
        self.assertEqual(humanoid["WalkSpeed"].kind, "property")
        self.assertEqual(humanoid["Died"].kind, "event")
        self.assertEqual(humanoid["MoveTo"].kind, "method")

    def test_deprecation_recorded(self):
        self.assertEqual(self.types["Humanoid"].members["LoadAnimation"].deprecated, "Animator:LoadAnimation")

    def test_static_tables(self):
        self.assertTrue(any(b.startswith("lookAt:") for b in self.tables["CFrame"]))
        self.assertTrue(any(b.startswith("wait:") for b in self.tables["task"]))

    def test_enum_items(self):
        items = self.types["EnumRaycastFilterType_INTERNAL"].members
        self.assertIn("Exclude", items)
        self.assertIn("Include", items)

    def test_docs_clean_html(self):
        self.assertEqual(roblox_api.clean("<code>Part</code> &amp; x"), "Part & x")


if __name__ == "__main__":
    unittest.main()
