"""Negative security fixture prevents a plugin launcher silently becoming game-script evidence."""
import importlib.util
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("recipe_contexts", ROOT / "tools/check_recipe_contexts.py")
assert spec and spec.loader
contexts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(contexts)

class RecipeContextTests(unittest.TestCase):
    def test_security_allowlist(self):
        with self.assertRaises(ValueError):
            contexts.analyze("", "RobloxScriptSecurity", False)

    @unittest.skipUnless(contexts.EXECUTABLE.exists() and
        (ROOT / ".cache/sources/luau-lsp/scripts/globalTypes.PluginSecurity.d.luau").exists(),
        "pinned definitions required")
    def test_launcher_is_not_game_script_callable(self):
        source = (ROOT / "examples/regression/PluginLauncher.lua.txt").read_text()
        for solver in (False, True):
            code, output = contexts.analyze(source, "None", solver)
            self.assertNotEqual(code, 0, "None context must reject plugin-only launcher")
            self.assertIn("ExecuteMultiplayerTestAsync", output)
            code, output = contexts.analyze(source, "PluginSecurity", solver)
            self.assertEqual(code, 0, output)
