"""check_content_budget must degrade, not crash, when tiktoken is installed but its encoding can't be fetched."""
from __future__ import annotations

import sys
import types
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

import check_content_budget  # noqa: E402


def broken_tiktoken() -> types.ModuleType:
    module = types.ModuleType("tiktoken")

    def get_encoding(name: str):
        raise OSError("Tunnel connection failed: 403 Forbidden")

    module.get_encoding = get_encoding
    return module


class OfflineTokenizer(unittest.TestCase):
    def test_falls_back_to_byte_bound(self):
        with mock.patch.dict(sys.modules, {"tiktoken": broken_tiktoken()}):
            report = check_content_budget.inspect()
        self.assertIn("unavailable", report["tokenizer"])

    def test_required_tokenizer_fails_with_a_clear_error(self):
        with mock.patch.dict(sys.modules, {"tiktoken": broken_tiktoken()}):
            with self.assertRaisesRegex(RuntimeError, "could not be loaded"):
                check_content_budget.inspect(require_tokenizer=True)


if __name__ == "__main__":
    unittest.main()
