"""Curated API coverage and ranking evidence tests; no Studio execution implied."""
from __future__ import annotations
import copy
import json
import re
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import api
import check_legacy
import rank_legacy
import render_legacy


class RankedLegacyCatalog(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = json.loads((ROOT / 'references/legacy-modernization/catalog.json').read_text(encoding='utf-8'))
        cls.ranking = rank_legacy.build()
        cls.entries = {e['id']: e for e in cls.data['entries']}

    def test_all_entries_have_detecting_fixtures_and_guidance(self):
        self.assertGreaterEqual(len(self.entries), 150)
        self.assertEqual(render_legacy.validate(self.data), [])
        for e in self.entries.values():
            with self.subTest(rule=e['id']):
                for field in ('old', 'new', 'why', 'when_ok', 'detect', 'verify', 'fixture'):
                    self.assertTrue(e[field])
                self.assertRegex(e['fixture'], e['detect'])

    def test_missing_or_nonmatching_fixture_is_rejected(self):
        data = copy.deepcopy(self.data)
        data['entries'][0]['fixture'] = 'task.wait(1)'
        self.assertTrue(any('fixture is not detected' in e for e in render_legacy.validate(data)))
        del data['entries'][0]['when_ok']
        self.assertTrue(any('missing when_ok' in e for e in render_legacy.validate(data)))

    def test_all_top150_rows_have_verified_detector_coverage(self):
        errors, report = check_legacy.validate(self.data, self.ranking, require_docs=False)
        self.assertEqual(errors, [])
        self.assertEqual(report['top_n'], 150)
        self.assertEqual(report['top_n_covered'], 150)
        self.assertGreaterEqual(report['explicitly_covered_rows'], 300)
        self.assertEqual(report['deprecated_rows'], len(api.rows('deprecated.tsv')))

    def test_scanner_detects_every_catalog_fixture(self):
        res = subprocess.run([sys.executable, str(ROOT / 'tools/scan_legacy.py'), '--no-api', '--json',
                              str(ROOT / 'references/legacy-modernization/fixtures.luau')],
                             capture_output=True, text=True, check=True)
        findings = json.loads(res.stdout)['findings']
        hits = {f['rule'] for f in findings}
        self.assertEqual(set(self.entries) - hits, set())

    def test_current_replacements_do_not_match_selected_rules(self):
        modern = {
            'sched-wait': 'task.wait(1)', 'sched-spawn': 'task.spawn(callback)',
            'query-findpartonray': 'workspace:Raycast(origin, direction, params)',
            'query-region3': 'workspace:GetPartBoundsInBox(cf, size, params)',
            'query-addtofilter': 'params.ExcludeInstances = {character}',
            'query-filtertype': 'params.IncludeInstances = {target}',
            'phys-velocity': 'part.AssemblyLinearVelocity = velocity',
            'phys-collision-group-queries': 'PhysicsService:GetRegisteredCollisionGroups()',
            'phys-bodymovers': 'local v = Instance.new("LinearVelocity")',
            'async-group-all-roles': 'GroupService:GetRolesInGroupAsync(userId, groupId)',
            'audio-sound-aliases': 'sound:Play()',
            'player-userid-alias': 'local id = player.UserId',
        }
        for rid, text in modern.items():
            with self.subTest(rule=rid):
                self.assertIsNone(re.search(self.entries[rid]['detect'], text))

    def test_ranking_covers_every_row_without_invented_frequencies(self):
        rows = self.ranking['rows']
        self.assertEqual(len(rows), len(api.rows('deprecated.tsv')))
        self.assertEqual(len({r['api'] for r in rows}), len(rows))
        self.assertEqual(self.ranking['evidence_status'], 'provisional')
        self.assertEqual(self.ranking['public_code_frequency']['status'], 'not_sampled')
        self.assertEqual(self.ranking['measured_model_outputs']['status'], 'not_sampled')
        self.assertTrue(all(r['public_code_frequency'] is None for r in rows))
        self.assertEqual([r['rank'] for r in rows], list(range(1, len(rows) + 1)))
        self.assertEqual(rows, sorted(rows, key=lambda r: (-r['score'], r['api'])))

    def test_task_wait_is_not_a_legacy_global_mention(self):
        row = next(r for r in api.rows('deprecated.tsv') if r['kind'] == 'global' and r['member'] == 'wait')
        self.assertIsNone(rank_legacy.mention_pattern(row).search('task.wait(1)'))
        self.assertIsNotNone(rank_legacy.mention_pattern(row).search('wait(1)'))

    def test_shared_member_name_is_not_evidence_for_wrong_receiver(self):
        row = next(r for r in api.rows('deprecated.tsv') if r['owner'] == 'GuiObject' and r['member'] == 'Transparency')
        self.assertIsNone(rank_legacy.mention_pattern(row).search('part.Transparency = 1'))
        self.assertIsNotNone(rank_legacy.mention_pattern(row).search('GuiObject.Transparency'))

    def test_provisional_ranking_blocks_release(self):
        for tool in ('rank_legacy.py', 'check_legacy.py'):
            res = subprocess.run([sys.executable, str(ROOT / 'tools' / tool), '--check', '--release-gate'],
                                 capture_output=True, text=True)
            self.assertNotEqual(res.returncode, 0)
            self.assertIn('BLOCKED', res.stdout)


class OfficialTutorialSample(unittest.TestCase):
    def test_only_language_labelled_code_fences_are_collected(self):
        import sample_legacy_tutorials as sample
        text = 'Prose wait()\n```text\nwait()\n```\n```luau title="Example"\nwait(1)\n```\n'
        blocks = sample.fenced_blocks(text)
        self.assertEqual(len(blocks), 1)
        self.assertEqual(blocks[0], (6, 'luau', 'wait(1)\n'))

    def test_comments_and_strings_are_masked_but_class_literals_survive(self):
        import sample_legacy_tutorials as sample
        text = '-- wait()\n--[=[ spawn() ]=]\nprint("delay()")\nlocal s = [=[getfenv()]=]\nlocal p = Instance.new("BodyVelocity")\nwait(1)'
        masked = sample.mask_noncode(text)
        self.assertNotIn('spawn', masked)
        self.assertNotIn('delay', masked)
        self.assertNotIn('getfenv', masked)
        self.assertIn('BodyVelocity', masked)
        self.assertEqual(masked.count('wait'), 1)
        self.assertEqual(masked.count('\n'), text.count('\n'))

    def test_tutorial_counts_are_explained_by_source_receipts(self):
        data = json.loads((ROOT / 'references/legacy-modernization/tutorial-sample.json').read_text())
        lock = json.loads((ROOT / 'sources/lock.json').read_text())
        self.assertEqual(data['source']['commit'], lock['sources']['creator-docs']['sha'])
        self.assertGreater(data['measurement']['code_blocks'], 1000)
        self.assertEqual(data['measurement']['matching_blocks'], len(data['matching_block_receipts']))
        counts = {}
        files = {}
        for receipt in data['matching_block_receipts']:
            for name in receipt['api_candidates']:
                counts[name] = counts.get(name, 0) + 1
                files.setdefault(name, set()).add(receipt['path'])
            self.assertRegex(receipt['file_sha256'], r'^[0-9a-f]{64}$')
            self.assertRegex(receipt['code_sha256'], r'^[0-9a-f]{64}$')
        for row in data['rows']:
            self.assertEqual(row['code_block_candidates'], counts.get(row['api'], 0))
            self.assertEqual(row['file_candidates'], len(files.get(row['api'], set())))


if __name__ == '__main__':
    unittest.main()
