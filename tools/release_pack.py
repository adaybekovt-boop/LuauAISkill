#!/usr/bin/env python3
"""Build and validate a distributable core/full ZIP; never conflates the two.
Runs local Python tests, link checks, available Luau tools, corpus integrity,
retrieval indexing and SHA256 inventory. It does not install tools or access
Roblox Studio. --require-corpus refuses packaging without BOTH mirrored sources.
"""
from __future__ import annotations
import argparse,hashlib,json,re,subprocess,sys
from datetime import datetime,timezone
from pathlib import Path
import build_index,check_links,make_zip,validate_examples,verify_pack,verify_corpus
ROOT=Path(__file__).resolve().parents[1]
def write(path:Path,value:object):
    path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def main()->int:
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--out',type=Path,default=ROOT.parent/'LuauAISkill-Core.zip');ap.add_argument('--require-corpus',action='store_true');a=ap.parse_args()
    qa=ROOT/'qa';qa.mkdir(exist_ok=True)
    proc=subprocess.run([sys.executable,'-m','unittest','discover','-s','tests','-v'],cwd=ROOT,text=True,encoding='utf-8',errors='replace',capture_output=True)
    log=proc.stdout+proc.stderr;(qa/'python-tests.log').write_text(log,encoding='utf-8')
    match=re.search(r'Ran (\d+) tests?',log)
    tests={'status':'PASS' if proc.returncode==0 else 'FAIL','command':'python -m unittest discover -s tests -v','test_count':int(match.group(1)) if match else None,'exit_code':proc.returncode,'log':'qa/python-tests.log','scope':'Python tooling tests; network flows use mocks; NOT live source downloads or Luau/Studio tests.'}
    links=check_links.check(ROOT);write(qa/'LINK-CHECKS.json',links)
    examples=validate_examples.validate(ROOT,None,None,False);write(qa/'EXAMPLE-CHECKS.json',examples)
    corpus=verify_corpus.verify(ROOT/'upstream');write(qa/'CORPUS-CHECKS.json',corpus)
    index=build_index.build(ROOT,ROOT/'indexes'/'knowledge.sqlite');index['database']='indexes/knowledge.sqlite'
    failed=proc.returncode!=0 or links['status']!='PASS' or any(r['status']=='FAIL' for r in examples['records']) or (a.require_corpus and corpus['status']!='PASS')
    counts={'handbook_chapters':len(list((ROOT/'handbook').glob('[0-9][0-9]-*.md'))),'recipes':len(list((ROOT/'recipes').glob('[0-9][0-9]-*.md'))),'tracks':len(list((ROOT/'tracks').glob('*.md')))-1,'agent_prompts':len(list((ROOT/'prompts').glob('[0-9][0-9]-*.md'))),'luau_files':len(list((ROOT/'examples').rglob('*.luau'))),'evaluation_tasks':sum(1 for s in (ROOT/'evals'/'cases.jsonl').read_text().splitlines() if s.strip()),'registered_source_urls':len(json.loads((ROOT/'sources'/'registry.json').read_text())['sources'])}
    report={'generated_at_utc':datetime.now(timezone.utc).isoformat(),'status':'FAIL' if failed else 'PASS_CORE_CHECKS' if corpus['status']!='PASS' else 'PASS_PACKAGE_AND_CORPUS_CHECKS','build_mode':'full-required' if a.require_corpus else 'core-permitted','counts':counts,'python_tests':tests,'relative_links':links,'corpus':corpus,'index':index,'example_checks':'qa/EXAMPLE-CHECKS.json','model_quality_evaluation':'NOT_RUN','roblox_studio':'NOT_RUN','live_github_workflow':'NOT_RUN_BY_THIS_BUILDER','remote_publication':'NOT_PERFORMED_BY_THIS_BUILDER','limits':['Core completeness is not official corpus completeness.','Missing Luau tools are recorded NOT_RUN, not PASS.','No FPS, visual-quality or model-quality improvement has been measured.','Network download tests use mocks; corpus integrity checks require actual local bodies.']}
    write(qa/'BUILD-REPORT.json',report)
    if failed:
        print(json.dumps(report,ensure_ascii=False,indent=2));print('BUILD FAILED. No completed ZIP created.',file=sys.stderr);return 1
    manifest=ROOT/'PACK-MANIFEST.json'
    write(manifest,{'format':1,'algorithm':'sha256','files':verify_pack.inventory(ROOT,manifest)})
    result=verify_pack.verify(ROOT,json.loads(manifest.read_text())['files'],manifest)
    if result['status']!='PASS':print('Integrity failed',file=sys.stderr);return 1
    archive=make_zip.make(ROOT,a.out)
    digest=a.out.with_suffix(a.out.suffix+'.sha256');digest.write_text(archive['sha256']+'  '+a.out.name+'\n',encoding='ascii')
    print(json.dumps({'build':report,'integrity':result,'archive':archive},ensure_ascii=False,indent=2));return 0
if __name__=='__main__':sys.exit(main())
