"""Fact binding/scope and embedded-registry rendering regression tests (offline)."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import check_fact_mentions as audit
import render_facts


def data():
    return {'facts': [{'id': 'test-limit', 'value': 10, 'statement': 'Example maximum.',
                       'unit': 'items', 'status': 'documented', 'evidence': ['At most 10 items.']},
                      {'id': 'test-range', 'value': [1, 8], 'statement': 'Example range.',
                       'unit': 'clients', 'status': 'documented', 'evidence': ['Between 1 and 8.']}]}


class FactMentions(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'references').mkdir()
        (self.root / 'handbook').mkdir()
        (self.root / 'SKILL.md').write_text('## Freshness snapshot\n')
        (self.root / 'references/limits.md').write_text('# Facts\n')

    def run_audit(self, text, filename='SKILL.md', facts=None):
        (self.root / filename).write_text(text)
        return audit.audit(self.root, facts or data())

    def test_unbound_number_and_beta_fail(self):
        result = self.run_audit('## Freshness snapshot\n- Cap 10 items.\n- Feature is beta.\n')
        self.assertEqual(result['unbound_blocks'], 2)
        self.assertEqual(len(result['errors']), 2)

    def test_valid_fact_id_and_numeric_evidence(self):
        result = self.run_audit('## Freshness snapshot\n- Cap <!-- fact-value: test-limit -->10<!-- /fact-value --> items.\n')
        self.assertFalse(result['errors'])
        self.assertEqual(result['covered_blocks'], 1)

    def test_unrelated_valid_id_does_not_cover_invented_number(self):
        result = self.run_audit('## Freshness snapshot\n- Cap 999 items. <!-- fact-refs: test-limit -->\n')
        self.assertEqual(result['unbound_blocks'], 1)
        self.assertTrue(any('numbers absent' in error for error in result['errors']))

    def test_unknown_fact_id_fails(self):
        result = self.run_audit('## Freshness snapshot\n- Cap 10. <!-- fact-refs: made-up -->\n')
        self.assertIn('unknown fact IDs', result['errors'][0])

    def test_inline_code_formulas_are_not_ignored(self):
        result = self.run_audit('## Freshness snapshot\n- Budget `60 + 40 * players`.\n')
        self.assertEqual(result['unbound_blocks'], 1)

    def test_fenced_code_and_link_destinations_are_not_claims(self):
        result = self.run_audit('## Freshness snapshot\n```lua\nlocal n = 100\n```\n- [guide](foo-123.md)\n')
        self.assertFalse(result['errors'])
        self.assertEqual(result['candidate_blocks'], 0)

    def test_other_skill_sections_are_outside_scope(self):
        result = self.run_audit('## Freshness snapshot\nNo numeric claim.\n## Workflow\n1. Do a thing.\n')
        self.assertFalse(result['errors'])
        self.assertEqual(result['outside_scope_review_candidates'], 0)

    def test_new_table_cannot_silently_escape_scope(self):
        result = self.run_audit('## Assorted facts\n| Item | Note |\n|---|---|\n| Widget | 999 instances |\n', 'handbook/new.md')
        self.assertEqual(result['outside_scope_review_candidates'], 1)
        self.assertTrue(result['errors'])

    def test_content_addressed_review_invalidated_by_edit(self):
        row = '| Widget | tune to 10 |'
        (self.root / 'maintainers').mkdir()
        (self.root / 'maintainers/fact-mention-review.json').write_text(json.dumps({'rows': [{
            'path': 'handbook/new.md', 'row_sha256': hashlib.sha256(row.encode()).hexdigest(),
            'classification': 'design_example', 'reason': 'Chosen game tuning; not an engine limit.'}]}))
        result = self.run_audit('## Tuning\n' + row, 'handbook/new.md')
        self.assertFalse(result['errors'])
        result = self.run_audit('## Tuning\n' + row.replace('10', '999'), 'handbook/new.md')
        self.assertTrue(result['errors'])

    def test_mixed_examples_do_not_exempt_other_numbers(self):
        row = '| Cap | <!-- fact-value: test-limit -->10<!-- /fact-value -->; tune 5 | <!-- fact-examples: {"values":["5"],"reason":"game tuning"} -->'
        (self.root / 'maintainers').mkdir()
        (self.root / 'maintainers/fact-mention-review.json').write_text(json.dumps({'rows': [{
            'path': 'handbook/new.md', 'row_sha256': hashlib.sha256(row.encode()).hexdigest(),
            'classification': 'mixed_examples', 'reason': 'game tuning', 'values': ['5']}]}))
        result = self.run_audit('## Limits\n' + row, 'handbook/new.md')
        self.assertFalse(result['errors'])
        result = self.run_audit('## Limits\n' + row.replace('tune 5', 'tune 6'), 'handbook/new.md')
        self.assertTrue(result['errors'])

    def test_inline_value_and_indexed_value_bind_ids(self):
        result = self.run_audit('## Freshness snapshot\n- Max <!-- fact-value: test-range[1] -->8<!-- /fact-value --> clients.\n')
        self.assertFalse(result['errors'])
        self.assertEqual(result['covered_blocks'], 1)

    def test_generated_table_rows_bind_ids(self):
        result = self.run_audit('## Limits\n| `test-limit`: Example maximum. | 10 | items | documented |', 'handbook/new.md')
        self.assertFalse(result['errors'])

    def test_number_notation(self):
        self.assertEqual(audit.number_key('10k'), audit.number_key('10,000'))
        self.assertEqual(audit.number_key('2^53'), audit.number_key('9007199254740992'))
        self.assertEqual(audit.number_key('−0.2'), '-0.2')

    def test_beta_claim_cannot_borrow_a_numeric_fact(self):
        result = self.run_audit('## Freshness snapshot\n- Feature is beta. <!-- fact-refs: test-limit -->\n')
        self.assertEqual(result['unbound_blocks'], 1)
        self.assertIn('statuses unsupported', result['errors'][0])

    def test_rollout_status_aliases_match_structured_status(self):
        facts = data()
        facts['facts'][0].update(status='ga', value='full release')
        for alias in ('GA', 'general availability', 'full release', 'fully released', 'stable'):
            with self.subTest(alias=alias):
                result = self.run_audit('## Freshness snapshot\n- Feature is '+alias+'. <!-- fact-refs: test-limit -->', facts=facts)
                self.assertFalse(result['errors'], result['errors'])
        result = self.run_audit('## Freshness snapshot\n- Feature is beta. <!-- fact-refs: test-limit -->', facts=facts)
        self.assertTrue(result['errors'])

    def test_negative_status_cannot_be_used_as_positive_support(self):
        facts = data()
        facts['facts'][0]['statement'] = 'The dump does not tag this API Deprecated.'
        negative = self.run_audit('## Freshness snapshot\n- The dump does not tag this API Deprecated. <!-- fact-refs: test-limit -->', facts=facts)
        self.assertFalse(negative['errors'])
        positive = self.run_audit('## Freshness snapshot\n- This API is Deprecated. <!-- fact-refs: test-limit -->', facts=facts)
        self.assertTrue(positive['errors'])

    def test_negation_cannot_be_inferred_from_ga(self):
        facts = data()
        facts['facts'][0].update(status='ga', value='full release')
        result = self.run_audit('## Freshness snapshot\n- Feature is not beta. <!-- fact-refs: test-limit -->', facts=facts)
        self.assertTrue(result['errors'])
        result = self.run_audit('## Freshness snapshot\n- Feature is not GA. <!-- fact-refs: test-limit -->', facts=facts)
        self.assertTrue(result['errors'])

    def test_incidental_historical_beta_does_not_override_ga(self):
        facts = data()
        facts['facts'][0].update(status='ga', value='full release', evidence=['Previously beta, now released.'])
        result = self.run_audit('## Freshness snapshot\n- Feature is beta. <!-- fact-refs: test-limit -->', facts=facts)
        self.assertTrue(result['errors'])

    def test_incidental_evidence_number_cannot_bless_limit(self):
        facts = data()
        facts['facts'][0]['evidence'] = ['Reviewed in 2026. The limit is 10.']
        facts['facts'][0]['notes'] = 'Review note 999.'
        for number in ('2026', '999'):
            with self.subTest(number=number):
                result = self.run_audit('## Freshness snapshot\n- Limit '+number+'. <!-- fact-refs: test-limit -->', facts=facts)
                self.assertTrue(result['errors'])
                self.assertEqual(result['unbound_blocks'], 1)

    def test_even_equal_raw_number_requires_rendered_binding(self):
        result = self.run_audit('## Freshness snapshot\n- Some limit is 10. <!-- fact-refs: test-limit -->')
        self.assertTrue(result['errors'])
        self.assertTrue(any('must use exact rendered' in e for e in result['errors']))

    def test_edited_value_block_rejected_even_when_equal_to_another_fact(self):
        result = self.run_audit('## Freshness snapshot\n- Limit <!-- fact-value: test-limit -->8<!-- /fact-value -->. <!-- fact-refs: test-range -->')
        self.assertTrue(result['errors'])
        self.assertTrue(any('differs from its registered' in e for e in result['errors']))

    def test_magic_words_cannot_self_exempt_new_claim(self):
        result = self.run_audit('## Freshness snapshot\n- Limit 999. <!-- fact-example: tuning, not a platform limit -->')
        self.assertTrue(result['errors'])
        self.assertTrue(any('lacks content-addressed' in e for e in result['errors']))

    def test_mixed_example_values_cannot_self_authorize(self):
        result = self.run_audit('## Freshness snapshot\n- Limit <!-- fact-value: test-limit -->10<!-- /fact-value -->; 999. <!-- fact-examples: {"values":["999"],"reason":"not a platform limit"} -->')
        self.assertTrue(result['errors'])
        self.assertTrue(any('lack matching content-addressed' in e for e in result['errors']))


    def test_repository_audit_is_explicitly_scoped(self):
        result = audit.audit(ROOT, json.loads((ROOT / 'references/facts.json').read_text()))
        self.assertFalse(result['errors'], result['errors'])
        self.assertGreater(len(result['adjudicated_non_limit_rows']), 50)
        self.assertIn('not semantic entailment', result['boundary'])


class EmbeddedFacts(unittest.TestCase):
    def test_render_table_and_indexed_value(self):
        text = 'Before\n<!-- facts-table: test-limit, test-range -->stale<!-- /facts-table -->\nMax <!-- fact-value: test-range[1] -->999<!-- /fact-value -->\nAfter'
        result = render_facts.render_embedded(text, data())
        self.assertIn('`test-limit`: Example maximum.', result)
        self.assertIn('<!-- fact-value: test-range[1] -->8<!-- /fact-value -->', result)
        self.assertTrue(result.startswith('Before\n'))
        self.assertTrue(result.endswith('\nAfter'))
        self.assertEqual(render_facts.render_embedded(result, data()), result)

    def test_unknown_render_id_and_duplicate_rows_fail(self):
        with self.assertRaises(KeyError):
            render_facts.render_embedded('<!-- fact-value: fake -->0<!-- /fact-value -->', data())
        with self.assertRaises(ValueError):
            render_facts.render_embedded('<!-- facts-table: test-limit, test-limit --><!-- /facts-table -->', data())


if __name__ == '__main__':
    unittest.main()
