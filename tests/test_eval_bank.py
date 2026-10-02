"""Offline D6 tests; no model or engine execution evidence."""
import copy
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import check_eval_bank as bank

class Bank(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / 'evals/cases').mkdir(parents=True)
        (self.root / 'evals/fixtures').mkdir()
        (self.root / 'evals/fixtures/broken.luau').write_text('local x = nil + 1\n')
        self.cases = [dict(id=f'T-{i}', category='test', kind='fixture', lang='ru' if i == 0 else 'en', prompt='Fix',
                           fixture='evals/fixtures/broken.luau',fixture_defect='nil arithmetic',must=['validate'],refs=['SKILL.md']) for i in range(8)]
        self.save_cases()
        bank.freeze_development(self.root)

    def tearDown(self): self.temp.cleanup()
    def save_cases(self):
        (self.root / 'evals/cases/test.jsonl').write_text('\n'.join(json.dumps(c) for c in self.cases)+'\n')
    def test_development_bank_honestly_pending(self):
        result=bank.audit(self.root)
        self.assertFalse(result['valid'])
        self.assertEqual(result['fraction'],0)
        self.assertEqual(result['categories']['test']['broken_code_fixtures'],8)
    def test_changed_prompt_breaks_hash(self):
        self.cases[0]['prompt']='different';self.save_cases()
        self.assertTrue(any('hash mismatch' in e for e in bank.audit(self.root)['errors']))
    def test_changed_fixture_breaks_hash(self):
        (self.root/'evals/fixtures/broken.luau').write_text('local x=0\n')
        self.assertTrue(any('hash mismatch' in e for e in bank.audit(self.root)['errors']))
    def test_cannot_relabel_known_development(self):
        p=self.root/'evals/split.json';s=json.loads(p.read_text());s['cases']['T-0'].update(exposure='sealed_holdout',provenance={'ever_development_exposed':False});p.write_text(json.dumps(s))
        self.assertIn('T-0: contaminated holdout',bank.audit(self.root)['errors'])
        with self.assertRaises(ValueError):bank.freeze_development(self.root)
    def test_external_seal_binds_new_cases(self):
        self.cases += [dict(self.cases[0],id=f'H-{i}') for i in range(4)]
        self.save_cases()
        p=self.root/'evals/split.json';s=json.loads(p.read_text())
        provenance=dict(external_author='external-author',custodian='operator',sealed_at='2026-10-02T00:00:00Z',skill_commit='frozen-test',skill_sha256='a'*64,no_development_use=True,ever_development_exposed=False)
        hashes={c['id']:bank.case_hash(c,self.root) for c in self.cases if c['id'].startswith('H-')}
        seal=self.root/'evals/seal.json';seal.write_text(json.dumps(dict(provenance,case_hashes=hashes)))
        provenance.update(seal_artifact='evals/seal.json',seal_sha256=hashlib.sha256(seal.read_bytes()).hexdigest())
        for cid,digest in hashes.items():s['cases'][cid]=dict(sha256=digest,exposure='sealed_holdout',provenance=provenance)
        p.write_text(json.dumps(s));self.assertTrue(bank.audit(self.root)['valid'])
        seal.write_text('{}');self.assertFalse(bank.audit(self.root)['valid'])
    def test_missing_fixture_attestation_is_not_broken_code_evidence(self):
        for c in self.cases:c.pop('fixture_defect')
        self.save_cases();bank.freeze_development(self.root)
        self.assertIn('test: missing documented broken-code fixture',bank.audit(self.root)['errors'])
    def test_unsafe_path_rejected(self):
        with self.assertRaises(ValueError):bank.safe_file(self.root,'../escape')

if __name__=='__main__':unittest.main()
