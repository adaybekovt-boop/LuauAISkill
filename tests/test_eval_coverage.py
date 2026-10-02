import importlib.util
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location('check_eval_coverage', Path(__file__).resolve().parents[1] / 'tools/check_eval_coverage.py')
audit = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(audit)


class CoverageTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / 'evals/cases').mkdir(parents=True)
        (self.root / 'evals/coverage').mkdir()
        self.case = {'id': 'TEST-01', 'must': ['server validates price'], 'refs': ['chapter.md']}
        (self.root / 'chapter.md').write_text('The server validates price against its own catalog.\n')
        self.write_case()
        self.review = {'case_id': 'TEST-01', 'must_index': 0, 'must': self.case['must'][0],
                       'must_sha256': hashlib.sha256(self.case['must'][0].encode()).hexdigest(),
                       'status': 'supported', 'reviewer': 'test reviewer', 'reviewed_at': '2026-10-02',
                       'rationale': 'The statement explicitly requires a server-owned catalog.',
                       'evidence': [{'ref': 'chapter.md', 'quote': 'The server validates price against its own catalog.'}]}

    def write_case(self):
        (self.root / 'evals/cases/test.jsonl').write_text(json.dumps(self.case) + '\n')

    def write_reviews(self, reviews=None):
        (self.root / 'evals/coverage/reviews.json').write_text(json.dumps({'schema_version': 1, 'reviews': reviews if reviews is not None else [self.review]}))

    def test_lexical_match_never_passes(self):
        result = audit.inspect(self.root)
        self.assertFalse(result['gate_passed'])
        self.assertEqual(result['counts']['unreviewed'], 1)
        self.assertTrue(result['obligations'][0]['candidates_not_proof'])

    def test_explicit_review_passes(self):
        self.write_reviews()
        result = audit.inspect(self.root)
        self.assertTrue(result['gate_passed'])
        self.assertEqual(result['reviewed_coverage_percent'], 100)

    def test_quote_drift_invalidates_review(self):
        self.write_reviews()
        (self.root / 'chapter.md').write_text('changed')
        self.assertEqual(audit.inspect(self.root)['counts']['invalid'], 1)

    def test_must_drift_invalidates_review(self):
        self.write_reviews()
        self.case['must'][0] = 'server validates price and balance'
        self.write_case()
        self.assertFalse(audit.inspect(self.root)['gate_passed'])

    def test_missing_hash_invalidates_review(self):
        self.review.pop('must_sha256')
        self.write_reviews()
        self.assertFalse(audit.inspect(self.root)['gate_passed'])

    def test_pending_correction_cannot_silently_replace_demand(self):
        self.write_reviews()
        (self.root / 'evals/coverage/criterion-corrections.json').write_text(json.dumps({'corrections': [{
            'case_id': 'TEST-01', 'must_index': 0, 'status': 'pending_adjudication',
            'original': 'some other original demand', 'corrected': self.case['must'][0]}]}))
        self.assertFalse(audit.inspect(self.root)['gate_passed'])

    def test_evidence_must_be_declared_ref(self):
        (self.root / 'other.md').write_text('The server validates price against its own catalog.')
        self.review['evidence'][0]['ref'] = 'other.md'
        self.write_reviews()
        self.assertEqual(audit.inspect(self.root)['counts']['invalid'], 1)

    def test_missing_quote_or_rationale_fails(self):
        for field in ('evidence', 'rationale', 'reviewer', 'reviewed_at'):
            original = self.review.pop(field)
            self.write_reviews()
            self.assertFalse(audit.inspect(self.root)['gate_passed'], field)
            self.review[field] = original

    def test_duplicate_and_orphan_reviews_fail(self):
        self.write_reviews([self.review, self.review])
        self.assertFalse(audit.inspect(self.root)['gate_passed'])
        orphan = dict(self.review, case_id='absent')
        self.write_reviews([self.review, orphan])
        self.assertFalse(audit.inspect(self.root)['gate_passed'])

    def test_missing_and_ambiguous_are_not_coverage(self):
        for status in ('missing', 'ambiguous'):
            self.review['status'] = status
            self.write_reviews()
            result = audit.inspect(self.root)
            self.assertFalse(result['gate_passed'])
            self.assertEqual(result['counts'][status], 1)

    def test_empty_bank_fails(self):
        (self.root / 'evals/cases/test.jsonl').unlink()
        self.assertFalse(audit.inspect(self.root)['gate_passed'])

    def test_ref_cannot_escape_root(self):
        self.case['refs'] = ['../outside.md']
        self.write_case()
        result = audit.inspect(self.root)
        self.assertFalse(result['gate_passed'])
        self.assertTrue(result['errors'])

    def test_duplicate_case_fails(self):
        (self.root / 'evals/cases/duplicate.jsonl').write_text(json.dumps(self.case) + '\n')
        self.assertTrue(audit.inspect(self.root)['errors'])


if __name__ == '__main__':
    unittest.main()
