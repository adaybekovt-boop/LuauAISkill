from __future__ import annotations
import hashlib,json,sys,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import check_links,publish_github,verify_corpus,verify_pack
class PublishValidation(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name);(self.root/'SKILL.md').write_text('skill')
        self.write_manifest()
    def tearDown(self):self.tmp.cleanup()
    def write_manifest(self):
        self.manifest=self.root/'PACK-MANIFEST.json';self.manifest.write_text(json.dumps({'format':1,'algorithm':'sha256','files':verify_pack.inventory(self.root,self.manifest)}))
    def test_verified_files(self):self.assertEqual(len(publish_github.verified_files(self.root)),2)
    def test_changed_file(self):
        (self.root/'SKILL.md').write_text('changed')
        with self.assertRaises(publish_github.PublishError):publish_github.verified_files(self.root)
    def test_unlisted_file_not_published(self):
        (self.root/'private-secret.txt').write_text('not included');self.assertEqual(len(publish_github.verified_files(self.root)),2)
    def test_missing_file(self):
        (self.root/'SKILL.md').unlink()
        with self.assertRaises(publish_github.PublishError):publish_github.verified_files(self.root)
    def test_env_refused_even_in_manifest(self):
        (self.root/'.env').write_text('placeholder');self.write_manifest()
        with self.assertRaises(publish_github.PublishError):publish_github.verified_files(self.root)
    def test_existing_remote_file_not_overwritten(self):
        checkout=self.root/'checkout';checkout.mkdir();(checkout/'SKILL.md').write_text('existing')
        with self.assertRaises(publish_github.PublishError):publish_github.install_files(self.root,checkout,[self.root/'SKILL.md'])
        self.assertEqual((checkout/'SKILL.md').read_text(),'existing')
    def test_matching_remote_file_allowed(self):
        checkout=self.root/'checkout';checkout.mkdir();(checkout/'SKILL.md').write_text('skill')
        self.assertEqual(publish_github.install_files(self.root,checkout,[self.root/'SKILL.md']),[])
    def test_empty_remote_copy(self):
        checkout=self.root/'checkout';checkout.mkdir()
        self.assertEqual(publish_github.install_files(self.root,checkout,[self.root/'SKILL.md']),['SKILL.md'])
    def test_symlink_refused(self):
        original=self.root/'SKILL.md';data=original.read_bytes();original.unlink();other=self.root/'other';other.write_bytes(data);original.symlink_to(other)
        with self.assertRaises(publish_github.PublishError):publish_github.verified_files(self.root)
class LinkChecks(unittest.TestCase):
    def setUp(self):self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name)
    def tearDown(self):self.tmp.cleanup()
    def test_valid_local(self):
        (self.root/'a.md').write_text('[B](b.md)');(self.root/'b.md').write_text('# B');self.assertEqual(check_links.check(self.root)['status'],'PASS')
    def test_missing_local(self):
        (self.root/'a.md').write_text('[B](b.md)');self.assertEqual(check_links.check(self.root)['status'],'FAIL')
    def test_external_not_counted(self):
        (self.root/'a.md').write_text('[B](https://example.org/b.md)');self.assertEqual(check_links.check(self.root)['checked_file_links'],0)
    def test_escape_rejected(self):
        (self.root/'a.md').write_text('[B](../outside.md)');self.assertEqual(check_links.check(self.root)['status'],'FAIL')
class RetrievalScope(unittest.TestCase):
    def test_workflow_files_are_not_knowledge_documents(self):
        import build_index
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);(root/'.github/workflows').mkdir(parents=True)
            (root/'.github/workflows/check.yml').write_text('pipeline only')
            (root/'guide.md').write_text('# Knowledge')
            self.assertEqual([p.name for p in build_index.candidates(root)],['guide.md'])

class CorpusChecks(unittest.TestCase):
    def setUp(self):self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name)
    def tearDown(self):self.tmp.cleanup()
    def test_missing_is_not_downloaded(self):self.assertEqual(verify_corpus.verify(self.root)['status'],'NOT_DOWNLOADED')
    def test_empty_report_is_not_complete(self):
        (self.root/'DOWNLOAD-REPORT.json').write_text(json.dumps({'complete_for_requested_sources':True,'corpora':[]}));self.assertEqual(verify_corpus.verify(self.root)['status'],'NOT_DOWNLOADED')
    def test_report_without_bodies_cannot_pass(self):
        (self.root/'DOWNLOAD-REPORT.json').write_text(json.dumps({'complete_for_requested_sources':True,'corpora':[{'source':s,'complete':True,'method':'github-tree-raw','repo':s+'/docs','sha':'a'*40} for s in ('roblox','luau')]}));self.assertEqual(verify_corpus.verify(self.root)['status'],'FAIL')

class LocalGitRoundtrip(unittest.TestCase):
    def test_publish_to_temporary_local_bare_repository(self):
        # Actual clone/commit/push/verify, but ONLY to a temporary local path.
        # This does not test GitHub authentication, network or workflow rollout.
        import contextlib,io,shutil,subprocess
        from unittest.mock import patch
        if not shutil.which('git'):self.skipTest('Local git executable not available')
        with tempfile.TemporaryDirectory() as temp:
            base=Path(temp);pack=base/'pack';pack.mkdir();bare=base/'remote.git'
            (pack/'SKILL.md').write_text('local test fixture, not a GitHub publication')
            manifest=pack/'PACK-MANIFEST.json'
            manifest.write_text(json.dumps({'format':1,'algorithm':'sha256','files':verify_pack.inventory(pack,manifest)}))
            subprocess.run(['git','init','--bare','--initial-branch=main',str(bare)],check=True,capture_output=True)
            real_which=shutil.which
            with patch.object(publish_github,'ROOT',pack),patch.object(publish_github,'REMOTE',str(bare)),patch.object(publish_github,'REPOSITORY','local-test-only'),patch.object(sys,'argv',['publish_github.py']),patch.object(publish_github.shutil,'which',side_effect=lambda name:None if name=='gh' else real_which(name)),contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(publish_github.main(),0)
            tree=subprocess.run(['git','--git-dir='+str(bare),'ls-tree','--name-only','main'],check=True,capture_output=True,text=True).stdout
            self.assertIn('SKILL.md',tree);self.assertIn('PACK-MANIFEST.json',tree)

if __name__=='__main__':unittest.main()
