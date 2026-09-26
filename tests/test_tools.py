"""Offline tests. Mocks verify downloader logic, NOT external endpoint availability."""
from __future__ import annotations
import hashlib,importlib.util,json,os,sqlite3,sys,tempfile,unittest,zipfile
from pathlib import Path
from unittest.mock import patch
from urllib.request import Request
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import fetch_corpus as fc
import build_index as bi
import search as se
import api_lookup as al
import make_zip as mz
import verify_pack as vp
import validate_examples as ve

class TempCase(unittest.TestCase):
    def setUp(self):self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name)
    def tearDown(self):self.tmp.cleanup()

class FetchValidation(TempCase):
    def test_official_urls(self):
        for h in fc.ALLOWED_HOSTS:self.assertEqual(fc.checked_url('https://'+h+'/a'),'https://'+h+'/a')
    def test_host_rejection(self):
        for u in ['https://evil.example/a','https://api.github.com.evil.example','https://evil.example@api.github.com/a','http://api.github.com','file:///tmp/a','https://api.github.com:444/a']:
            with self.subTest(u=u),self.assertRaises(ValueError):fc.checked_url(u)
    def test_explicit_https_port(self):self.assertEqual(fc.checked_url('https://api.github.com:443/a'),'https://api.github.com:443/a')
    def test_safe_nested_path(self):self.assertEqual(fc.safe_path(self.root,'docs/types/a.md'),self.root/'docs/types/a.md')
    def test_unsafe_paths(self):
        for p in ['', '.', '../x','a/../../x','/tmp/x','a\\b','C:/x','a:x','a\x00b']:
            with self.subTest(p=p),self.assertRaises(ValueError):fc.safe_path(self.root,p)
    def test_symlink_escape(self):
        with tempfile.TemporaryDirectory() as other:
            try:(self.root/'link').symlink_to(other,target_is_directory=True)
            except (OSError,NotImplementedError):self.skipTest('symlinks unavailable')
            with self.assertRaises(ValueError):fc.safe_path(self.root,'link/x')
    def test_blob_known_empty(self):self.assertEqual(fc.git_blob_sha(b''),'e69de29bb2d1d6434b8b29ae775ad8c2e48c5391')
    def test_atomic_replace(self):
        p=self.root/'a'/'b.txt';fc.atomic_write(p,b'old');fc.atomic_write(p,b'new');self.assertEqual(p.read_bytes(),b'new');self.assertFalse(p.with_name('b.txt.part').exists())
    def test_json_roundtrip(self):
        p=self.root/'a.json';fc.write_json(p,{'ru':'проверка'});self.assertEqual(json.loads(p.read_text()),{'ru':'проверка'})
    def test_roblox_asset_guides_included(self):self.assertTrue(fc.selected('roblox',{'type':'blob','path':'content/en-us/assets/manager.md'}))
    def test_binary_media_excluded(self):self.assertFalse(fc.selected('roblox',{'type':'blob','path':'content/en-us/assets/test.png'}))
    def test_translation_excluded(self):self.assertFalse(fc.selected('roblox',{'type':'blob','path':'content/ru-ru/a.md'}))
    def test_yaml_selected(self):self.assertTrue(fc.selected('roblox',{'type':'blob','path':'content/en-us/reference/engine/classes/Lighting.yaml'}))
    def test_symlink_not_selected(self):self.assertFalse(fc.selected('roblox',{'type':'blob','mode':'120000','path':'content/en-us/x.md'}))
    def test_license_selected(self):
        for key in ['roblox','luau']:
            for name in ['LICENSE','LICENSE-CODE','LICENSE.md']:self.assertTrue(fc.selected(key,{'type':'blob','path':name}))
    def test_luau_vendor_excluded(self):self.assertFalse(fc.selected('luau',{'type':'blob','path':'node_modules/any/README.md'}))
    def test_luau_docs_selected(self):self.assertTrue(fc.selected('luau',{'type':'blob','path':'src/content/docs/syntax.md'}))
    def test_index_exact_links(self):
        text='[A](/docs/a.md) [B](https://create.roblox.com/docs/b.md#part) [again](/docs/a.md) [bad](https://evil.example/docs/c.md) [query](/docs/q.md?x=1) [html](/docs/h)'
        self.assertEqual(fc.index_links(text),['https://create.roblox.com/docs/a.md','https://create.roblox.com/docs/b.md'])
    def test_index_invalid_no_links(self):self.assertEqual(fc.index_links('empty'),[])
    def test_redirect_rejects_before_follow(self):
        with self.assertRaises(ValueError):fc.SafeRedirect().redirect_request(Request('https://api.github.com/a'),None,302,'Found',{},'https://evil.example/steal')
    def test_redirect_strips_auth_cross_host(self):
        req=Request('https://api.github.com/a',headers={'Authorization':'Bearer TEST_ONLY'})
        new=fc.SafeRedirect().redirect_request(req,None,302,'Found',{},'https://raw.githubusercontent.com/a')
        self.assertIsNone(new.get_header('Authorization'))
    def test_redirect_same_host_retains_auth(self):
        req=Request('https://api.github.com/a',headers={'Authorization':'Bearer TEST_ONLY'})
        new=fc.SafeRedirect().redirect_request(req,None,302,'Found',{},'https://api.github.com/b')
        self.assertEqual(new.get_header('Authorization'),'Bearer TEST_ONLY')

class FetchFlow(TempCase):
    def test_tree_complete(self):
        entries=[{'path':'a.md','type':'blob','sha':'b'}]
        with patch.object(fc,'get_json',return_value={'tree':entries,'truncated':False}):self.assertEqual(fc.enumerate_tree('x/y','sha'),entries)
    def test_missing_tree_refused(self):
        with patch.object(fc,'get_json',return_value={}),self.assertRaises(ValueError):fc.enumerate_tree('x/y','sha')
    def test_truncated_fallback(self):
        root={'tree':[{'path':'docs','type':'tree','sha':'sub'},{'path':'LICENSE','type':'blob','sha':'l'}]}
        sub={'tree':[{'path':'a.md','type':'blob','sha':'a'}]}
        def get(url):return {'truncated':True,'tree':[]} if '?' in url else sub if url.endswith('/sub') else root
        with patch.object(fc,'get_json',side_effect=get):
            out=fc.enumerate_tree('x/y','root');self.assertEqual({x['path'] for x in out},{'docs','LICENSE','docs/a.md'})
    def test_nonrecursive_truncated_refused(self):
        with patch.object(fc,'get_json',return_value={'tree':[],'truncated':True}),self.assertRaises(RuntimeError):fc.enumerate_tree('x/y','sha')
    def mock_repository(self,body=b'# Guide\nVerified mock fixture\n'):
        docs={'LICENSE':b'TEST FIXTURE LICENSE\n','content/en-us/a.md':body}
        entries=[{'type':'blob','path':p,'sha':fc.git_blob_sha(b)} for p,b in docs.items()]
        pin={'repo':'Test/Repo','sha':'a'*40,'commit_date':'fixture'}
        def fetch(url):
            for p,b in docs.items():
                if url.endswith('/'+p):return b
            raise AssertionError('Unknown fixture URL')
        return docs,entries,pin,fetch
    def test_mirror_complete_with_mocks(self):
        docs,entries,pin,get=self.mock_repository()
        with patch.object(fc,'resolve_pin',return_value=pin),patch.object(fc,'enumerate_tree',return_value=entries),patch.object(fc,'fetch',side_effect=get):
            report=fc.mirror_repo('roblox',self.root,2,False)
        self.assertTrue(report['complete']);self.assertEqual(report['saved_files'],2)
        self.assertTrue((self.root/'Test__Repo__aaaaaaaaaaaa'/'MIRROR-MANIFEST.json').exists())
    def test_mirror_partial_not_complete(self):
        docs,entries,pin,get=self.mock_repository()
        def fail(url):
            if url.endswith('a.md'):raise OSError('fixture unavailable')
            return get(url)
        with patch.object(fc,'resolve_pin',return_value=pin),patch.object(fc,'enumerate_tree',return_value=entries),patch.object(fc,'fetch',side_effect=fail):r=fc.mirror_repo('roblox',self.root,2,False)
        self.assertFalse(r['complete']);self.assertEqual(r['saved_files'],1);self.assertEqual(len(r['errors']),1)
    def test_mirror_checksum_failure(self):
        docs,entries,pin,get=self.mock_repository()
        def corrupt(url):return b'wrong' if url.endswith('a.md') else get(url)
        with patch.object(fc,'resolve_pin',return_value=pin),patch.object(fc,'enumerate_tree',return_value=entries),patch.object(fc,'fetch',side_effect=corrupt):r=fc.mirror_repo('roblox',self.root,2,False)
        self.assertFalse(r['complete']);self.assertIn('SHA mismatch',r['errors'][0]['detail'])
    def test_mirror_verified_reuse(self):
        docs,entries,pin,get=self.mock_repository()
        with patch.object(fc,'resolve_pin',return_value=pin),patch.object(fc,'enumerate_tree',return_value=entries),patch.object(fc,'fetch',side_effect=get):fc.mirror_repo('roblox',self.root,1,False)
        with patch.object(fc,'resolve_pin',return_value=pin),patch.object(fc,'enumerate_tree',return_value=entries),patch.object(fc,'fetch',side_effect=AssertionError('must reuse')):r=fc.mirror_repo('roblox',self.root,1,False)
        self.assertTrue(r['complete'])
    def test_mirror_lfs_pointer_refused(self):
        docs,entries,pin,get=self.mock_repository(b'version https://git-lfs.github.com/spec/v1\noid sha256:fake\nsize 1\n')
        with patch.object(fc,'resolve_pin',return_value=pin),patch.object(fc,'enumerate_tree',return_value=entries),patch.object(fc,'fetch',side_effect=get):r=fc.mirror_repo('roblox',self.root,1,False)
        self.assertFalse(r['complete']);self.assertIn('LFS pointer',r['errors'][0]['detail'])
    def test_existing_lfs_pointer_refused(self):
        docs,entries,pin,get=self.mock_repository(b'version https://git-lfs.github.com/spec/v1\noid sha256:fake\nsize 1\n')
        p=self.root/'Test__Repo__aaaaaaaaaaaa'/'content/en-us/a.md';p.parent.mkdir(parents=True);p.write_bytes(docs['content/en-us/a.md'])
        with patch.object(fc,'resolve_pin',return_value=pin),patch.object(fc,'enumerate_tree',return_value=entries),patch.object(fc,'fetch',side_effect=get):r=fc.mirror_repo('roblox',self.root,1,False)
        self.assertFalse(r['complete'])
    def test_mirror_license_required(self):
        with patch.object(fc,'resolve_pin',return_value={'repo':'Test/Repo','sha':'a'*40}),patch.object(fc,'enumerate_tree',return_value=[{'type':'blob','path':'content/en-us/a.md'}]),self.assertRaises(RuntimeError):fc.mirror_repo('roblox',self.root,1,False)

class LocalIndex(TempCase):
    def setUp(self):
        super().setUp();(self.root/'handbook').mkdir();(self.root/'handbook/a.md').write_text('# Освещение\n\nLightingStyle и PBR\n',encoding='utf-8');(self.root/'handbook/b.md').write_text('# Data\n\nUpdateAsync save\n');self.db=self.root/'indexes/knowledge.sqlite';bi.build(self.root,self.db)
    def test_index_counts(self):
        c=sqlite3.connect(self.db)
        try:self.assertEqual(c.execute('select count(*) from files').fetchone()[0],2)
        finally:c.close()
    def test_ru_search(self):self.assertEqual(se.search(self.db,'освещение',root=self.root)[0]['path'],'handbook/a.md')
    def test_english_api_search(self):self.assertEqual(se.search(self.db,'UpdateAsync',root=self.root)[0]['path'],'handbook/b.md')
    def test_stale_hash_detected(self):
        (self.root/'handbook/a.md').write_text('changed');self.assertTrue(se.search(self.db,'LightingStyle',root=self.root)[0]['stale_index'])
    def test_missing_source_detected(self):
        (self.root/'handbook/a.md').unlink();self.assertTrue(se.search(self.db,'LightingStyle',root=self.root)[0]['stale_index'])
    def test_no_match_returns_empty(self):self.assertEqual(se.search(self.db,'noSuchTokenZebra',root=self.root),[])
    def test_empty_query(self):self.assertEqual(se.search(self.db,'()!"',root=self.root),[])
    def test_user_query_does_not_inject_sql(self):
        se.search(self.db,'"; DROP TABLE files; --',root=self.root);self.assertEqual(len(se.search(self.db,'UpdateAsync',root=self.root)),1)
    def test_synonym_expansion(self):self.assertIn('LightingStyle',se.terms('освещение'))
    def test_evals_excluded(self):
        (self.root/'evals').mkdir();(self.root/'evals/answers.md').write_text('# SecretRubricUnique');bi.build(self.root,self.db);self.assertEqual(se.search(self.db,'SecretRubricUnique',root=self.root),[])
    def test_chunk_line_integrity(self):
        text='\n'.join('line '+str(i) for i in range(500));chunks=list(bi.chunks(text));self.assertEqual(chunks[0][0],1);self.assertEqual(chunks[-1][1],500);self.assertEqual('\n'.join(x[2] for x in chunks),text)
    def test_fenced_block_not_split_at_blank(self):
        text='```luau\n'+'\n'.join('local x = 1' for _ in range(80))+'\n\n```\n';self.assertEqual(len(list(bi.chunks(text))),1)

class ApiAndPackaging(TempCase):
    def test_exact_member_boundaries(self):
        text='properties:\n  - name: Lighting.A\n    type: number\n  - name: Lighting.ABC\n    type: string\nmethods:\n';v=al.extract(text,'Lighting.A');self.assertEqual(v[:2],(2,3));self.assertNotIn('ABC',v[2])
    def test_missing_member_is_none(self):self.assertIsNone(al.extract('properties:\n  - name: Lighting.A\n','Lighting.B'))
    def test_last_member(self):self.assertEqual(al.extract('properties:\n  - name: Lighting.A\n    type: float\n','Lighting.A')[1],3)
    def test_member_regex_escaped(self):self.assertIsNone(al.extract('  - name: LightingxA\n','Lighting.A'))
    def test_zip_crc_and_no_cache(self):
        (self.root/'a.txt').write_text('fixture');(self.root/'__pycache__').mkdir();(self.root/'__pycache__/a.pyc').write_bytes(b'x');out=self.root/'out.zip';report=mz.make(self.root,out)
        self.assertEqual(report['files'],1)
        with zipfile.ZipFile(out) as z:self.assertIsNone(z.testzip());self.assertEqual(len(z.namelist()),1)
    def test_manifest_change_detected(self):
        (self.root/'a.txt').write_text('original');m=self.root/'PACK-MANIFEST.json';expected=vp.inventory(self.root,m);(self.root/'a.txt').write_text('changed');self.assertEqual(vp.verify(self.root,expected,m)['status'],'FAIL')
    def test_manifest_extra_reported(self):
        (self.root/'a.txt').write_text('original');m=self.root/'PACK-MANIFEST.json';expected=vp.inventory(self.root,m);(self.root/'new.txt').write_text('new');r=vp.verify(self.root,expected,m);self.assertEqual(r['status'],'PASS');self.assertEqual(r['additional_files'],['new.txt'])
    def test_manifest_missing_reported(self):
        (self.root/'a.txt').write_text('original');m=self.root/'PACK-MANIFEST.json';expected=vp.inventory(self.root,m);(self.root/'a.txt').unlink();self.assertEqual(vp.verify(self.root,expected,m)['missing'],['a.txt'])
    def test_no_luau_tool_is_not_run(self):
        with patch.object(ve.shutil,'which',return_value=None):report=ve.validate(ROOT,None,None,False)
        self.assertTrue(all(x['status']=='NOT_RUN' for x in report['records']))
    def test_runner_command_failure(self):
        r=ve.run([sys.executable,'-c','raise SystemExit(7)'],self.root);self.assertEqual(r['status'],'FAIL');self.assertEqual(r['exit_code'],7)
    def test_runner_command_success(self):
        r=ve.run([sys.executable,'-c','print("fixture")'],self.root);self.assertEqual(r['status'],'PASS');self.assertIn('fixture',r['stdout'])

class PackStructure(unittest.TestCase):
    def test_registry_unique_and_real_ids(self):
        s=json.loads((ROOT/'sources/registry.json').read_text())['sources'];ids=[x['id'] for x in s];self.assertEqual(len(ids),len(set(ids)));self.assertGreaterEqual(len(ids),60)
    def test_example_manifest_matches_files(self):
        m=json.loads((ROOT/'examples/MANIFEST.json').read_text());listed={x['path'] for x in m['examples']};actual={p.relative_to(ROOT).as_posix() for p in (ROOT/'examples').rglob('*.luau')};self.assertEqual(listed,actual)
    def test_evals_sources_and_references(self):
        ids={x['id'] for x in json.loads((ROOT/'sources/registry.json').read_text())['sources']};cases=[json.loads(x) for x in (ROOT/'evals/cases.jsonl').read_text().splitlines()];self.assertEqual(len(cases),96)
        for c in cases:
            self.assertTrue(set(c['source_ids'])<=ids);self.assertEqual(len(c['criteria']),3);self.assertIsNone(c['score']);self.assertEqual(c['status'],'NOT_RUN')
            for ref in c['reference_chapters']:self.assertTrue((ROOT/ref).is_file())
    def test_prompts_have_no_answer_key(self):
        for line in (ROOT/'evals/prompts-only.jsonl').read_text().splitlines():self.assertNotIn('criteria',json.loads(line))
    def test_handbook_index_exists(self):
        data=json.loads((ROOT/'reference/handbook-index.json').read_text());self.assertEqual(len(data),48)
        for record in data:self.assertTrue((ROOT/record['path']).is_file())

if __name__=='__main__':unittest.main(verbosity=2)
