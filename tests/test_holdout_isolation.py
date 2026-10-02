"""Heldout prompts must never update the skill's legacy ranking."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import rank_legacy
class HoldoutIsolation(unittest.TestCase):
    def test_ranking_reads_only_development_cases_not_heldout_fixtures(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'evals/cases').mkdir(parents=True)
            (root / 'evals/development-exposure.json').write_text(json.dumps(['DEV']))
            cases = [{'id':'DEV','prompt':'development'},
                     {'id':'SEALED','prompt':'never use for tuning','fixture':'does-not-exist'}]
            (root/'evals/cases/test.jsonl').write_text('\n'.join(json.dumps(c) for c in cases))
            with patch.object(rank_legacy,'ROOT',root):
                self.assertEqual(rank_legacy.eval_corpus(), [('DEV','development')])
    def test_explicit_holdout_excluded_even_if_exposure_ledger_is_corrupt(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/'evals/cases').mkdir(parents=True)
            (root/'evals/development-exposure.json').write_text('["SEALED"]')
            (root/'evals/split.json').write_text(json.dumps({'cases':{'SEALED':{'exposure':'sealed_holdout'}}}))
            (root/'evals/cases/test.jsonl').write_text(json.dumps({'id':'SEALED','prompt':'hidden','fixture':'missing'}))
            with patch.object(rank_legacy,'ROOT',root):
                self.assertEqual(rank_legacy.eval_corpus(), [])
if __name__=='__main__': unittest.main()
