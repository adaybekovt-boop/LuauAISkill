#!/usr/bin/env python3
"""Verify bodies from BOTH official sources against their mirror manifests.
Manifest checks verify local consistency, not source authorship or rollout.
A root report without saved documents can never pass.
"""
from __future__ import annotations
import argparse,hashlib,json,sys
from pathlib import Path
from fetch_corpus import safe_path,git_blob_sha
ROOT=Path(__file__).resolve().parents[1]
def verify(upstream:Path)->dict:
    report=upstream/'DOWNLOAD-REPORT.json'
    if not report.is_file():return {'status':'NOT_DOWNLOADED','checked_files':0,'errors':['Missing DOWNLOAD-REPORT.json']}
    try:data=json.loads(report.read_text(encoding='utf-8'))
    except (ValueError,OSError) as e:return {'status':'FAIL','checked_files':0,'errors':[str(e)]}
    corpora=data.get('corpora',[])
    if not corpora:return {'status':'NOT_DOWNLOADED','checked_files':0,'errors':[data.get('reason','No mirrored sources in report')]}
    errors=[];checked=0
    if {c.get('source') for c in corpora}!={'roblox','luau'}:errors.append('Both Roblox and Luau are required for a full pack')
    if not data.get('complete_for_requested_sources'):errors.append('Downloader reported an incomplete result')
    for corpus in corpora:
        source=corpus.get('source','unknown')
        if not corpus.get('complete'):errors.append(source+': incomplete');continue
        try:
            if corpus.get('method')=='official-markdown-indexes':folder=upstream/'Roblox__website'
            elif corpus.get('method')=='github-tree-raw':
                folder=safe_path(upstream,corpus['repo'].replace('/','__')+'__'+corpus['sha'][:12])
            else:raise ValueError('Unknown mirror method')
            manifest=json.loads((folder/'MIRROR-MANIFEST.json').read_text(encoding='utf-8'))
            records=manifest.get('files',[])
            expected=manifest.get('expected_files',manifest.get('expected_pages'))
            saved=manifest.get('saved_files',manifest.get('saved_pages'))
            if not manifest.get('complete') or manifest.get('errors') or not records or len(records)!=expected or saved!=expected:
                raise ValueError('Incomplete manifest or count mismatch')
            if manifest.get('source')!=source:raise ValueError('Source identity mismatch')
            if corpus.get('sha') and (manifest.get('sha')!=corpus['sha'] or manifest.get('repo')!=corpus['repo']):raise ValueError('Commit/repository mismatch')
            paths=[r.get('path') for r in records]
            if len(paths)!=len(set(paths)):raise ValueError('Duplicate manifest paths')
            if not any(p.is_file() and p.name.upper().startswith(('LICENSE','COPYING')) for p in folder.iterdir()):raise ValueError('Missing license')
            for record in records:
                p=safe_path(folder,record['path'])
                if not p.is_file():errors.append(source+': missing '+record['path']);continue
                raw=p.read_bytes()
                if len(raw)!=record.get('bytes') or hashlib.sha256(raw).hexdigest()!=record.get('sha256'):
                    errors.append(source+': changed '+record['path']);continue
                if record.get('git_blob_sha') and git_blob_sha(raw)!=record['git_blob_sha']:
                    errors.append(source+': Git blob mismatch '+record['path']);continue
                checked+=1
        except (KeyError,ValueError,OSError) as e:errors.append(source+': '+str(e))
    return {'status':'PASS' if not errors else 'FAIL','checked_files':checked,'errors':errors,'meaning':'Verifies saved text of both declared sources; does not cover excluded media, every public Roblox page, future versions or Studio rollout.'}
def main()->int:
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--upstream',type=Path,default=ROOT/'upstream');a=ap.parse_args()
    r=verify(a.upstream);print(json.dumps(r,ensure_ascii=False,indent=2));return 0 if r['status']=='PASS' else 2 if r['status']=='NOT_DOWNLOADED' else 1
if __name__=='__main__':sys.exit(main())
