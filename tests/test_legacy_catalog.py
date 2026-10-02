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

    def test_external_corpus_is_not_a_release_gate(self):
        res = subprocess.run([sys.executable, str(ROOT / 'tools/rank_legacy.py'), '--check', '--release-gate'],
                             capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, res.stdout)
        res = subprocess.run([sys.executable, str(ROOT / 'tools/check_legacy.py'), '--check', '--release-gate'],
                             capture_output=True, text=True)
        self.assertNotEqual(res.returncode, 0)
        self.assertIn('D3 unresolved migration evidence', res.stdout)

    def test_dump_coverage_executes_detectors_for_every_row(self):
        import classify_legacy
        report = classify_legacy.build()
        self.assertEqual(report['detected_all_rows'], report['total_deprecated_rows'])
        self.assertEqual(report['detected_relevant_rows'], report['relevant_rows'])
        self.assertTrue(report['remaining_curation'])
        self.assertEqual(report['unreviewed_rows'], 0)
        self.assertTrue(all(r['curated_detector_verified'] for r in report['rows'] if r['relevant'] and r['classification'] == 'curated'))
        self.assertEqual(report['ab_output_curation']['status'], 'not_measured')
        self.assertTrue(all(r['fixture'] and r['source'] and r['scope_reason'] for r in report['rows']))

    def test_semantic_changes_are_curated_not_renamed(self):
        import classify_legacy
        rows = {r['api']: r for r in classify_legacy.build()['rows']}
        for name in ('CaptureService.CaptureSaved', 'Stats.HeartbeatTimeMs', 'BasePart.GetRootPart',
                     'InputAction.Fire', 'SelectionBox.SurfaceColor', 'TeleportService.TeleportToSpawnByName'):
            with self.subTest(api=name):
                self.assertEqual(rows[name]['classification'], 'curated')
                self.assertTrue(rows[name]['curated_detector_verified'])
        self.assertEqual(rows['ClickDetector.mouseClick']['classification'], 'one_to_one')
        self.assertFalse(rows['VoiceChatInternal.JoinByGroupId']['relevant'])

    def test_dated_staff_evidence_is_pinned_and_scoped(self):
        receipts = [r for e in self.entries.values() for r in e.get('reviewed_sources', [])]
        self.assertEqual(len(receipts), 6)
        for receipt in receipts:
            self.assertEqual(render_legacy.validate_reviewed_source(receipt), [])
            bad = dict(receipt, sha256='0' * 64)
            self.assertIn('reviewed source artifact hash mismatch', render_legacy.validate_reviewed_source(bad))
            source = json.loads((ROOT / receipt['artifact']).read_text())
            self.assertTrue(source['scope'])
            self.assertTrue(source['limitations'])
            self.assertIn('not an HTML/screenshot archive', source['capture_method'])
        self.assertTrue(render_legacy.validate_reviewed_source({'artifact': '../../escape.json', 'sha256': ''}))
        self.assertNotIn('AccessoryDescription.Puffiness', self.entries['layered-fit-retired-tuning']['covers'])
        self.assertNotIn('PlayerGui.GetTopbarTransparency', self.entries['topbar-transparency-setter-retired']['covers'])
        self.assertEqual(self.entries['hinge-softlock-retired']['covers'], ['HingeConstraint.SoftlockServoUponReachingTarget'])

    def test_scanner_metadata_preserves_all_dump_candidates_after_dedup(self):
        import tempfile
        import classify_legacy
        rows = api.rows('deprecated.tsv')
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'all.luau'
            path.write_text('\n'.join(classify_legacy.fixture(r) for r in rows))
            res = subprocess.run([sys.executable, '-I', str(ROOT / 'tools/scan_legacy.py'), str(path), '--json'],
                                 capture_output=True, text=True, check=True, cwd=directory)
            candidates = {name for f in json.loads(res.stdout)['findings'] for name in f['api_candidates']}
        self.assertEqual({rank_legacy.identifier(r) for r in rows} - candidates, set())

    def test_shared_receiver_and_lowercase_names_are_detection_candidates(self):
        import scan_legacy
        rules = {rid: rx for rid, rx, _ in scan_legacy.load_rules(True)}
        self.assertRegex('unknown.Transparency = 1', rules['api-deprecated:GuiObject.Transparency'])
        self.assertRegex('mouse.hit', rules['api-deprecated:Mouse.hit'])
        self.assertRegex('mouse["hit"]', rules['api-deprecated:Mouse.hit'])
        self.assertRegex('local x = Enum.KeyCode.World0', rules['api-deprecated:Enum.KeyCode.World0'])


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
