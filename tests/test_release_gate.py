import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import check_release

class ReleaseGateTests(unittest.TestCase):
    def test_missing_host_receipts_blocks(self):
        with tempfile.TemporaryDirectory() as directory:
            ok, reason = check_release.check_host_evidence(Path(directory) / 'missing.json')
            self.assertFalse(ok)
            self.assertIn('missing', reason)

    def test_filesystem_packaging_is_not_host_acceptance(self):
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory) / 'receipts.json'
            file.write_text(json.dumps({'hosts': [{'host': host, 'status': 'PACKAGE_VALIDATED'} for host in check_release.HOSTS]}))
            ok, reason = check_release.check_host_evidence(file)
            self.assertFalse(ok)
            self.assertIn('pending', reason)

    def test_all_host_variants_required(self):
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory) / 'receipts.json'
            file.write_text(json.dumps({'hosts': [{'host': 'codex', 'status': 'VERIFIED'}]}))
            self.assertFalse(check_release.check_host_evidence(file)[0])

if __name__ == '__main__':
    unittest.main()
