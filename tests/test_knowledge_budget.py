"""D5 authored knowledge must fit the navigation-sized token budget."""
import importlib.util
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import check_content_budget

class KnowledgeBudget(unittest.TestCase):
    def test_large_authored_knowledge_fails_but_generated_lookup_does_not(self):
        encoder = types.SimpleNamespace(encode=lambda text, **kw: list(text))
        fake = types.SimpleNamespace(get_encoding=lambda name: encoder)
        with tempfile.TemporaryDirectory() as directory, patch.dict(sys.modules, {'tiktoken': fake}):
            root = Path(directory)
            (root / 'SKILL.md').write_text('router')
            refs = root / 'references/legacy-modernization'
            refs.mkdir(parents=True)
            (refs / 'CATALOG.md').write_text('x' * 8001)
            (root / 'references/authored.md').write_text('x' * 8001)
            result = check_content_budget.inspect(root, require_tokenizer=True)
            self.assertEqual(len(result['errors']), 1)
            self.assertIn('authored.md', result['errors'][0])
            self.assertEqual(len(result['outliers']), 2)

if __name__ == '__main__':
    unittest.main()
