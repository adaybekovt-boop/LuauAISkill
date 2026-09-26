#!/usr/bin/env python3
"""Verify hashes of shipped files; not a test of their correctness or source completeness.
Additional files from later corpus downloads are allowed and reported, not silently deleted.
--write creates a new inventory for your current files; do not confuse it with original provenance.
"""
from __future__ import annotations
import argparse,hashlib,json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
EXCLUDE={'.git','__pycache__','.pytest_cache','.toolchain'}
def inventory(root:Path,manifest:Path)->dict:
    result={}
    for p in sorted(root.rglob('*')):
        if not p.is_file() or p.is_symlink() or p.resolve()==manifest.resolve():continue
        rel=p.relative_to(root)
        if any(x in EXCLUDE for x in rel.parts) or p.suffix in {'.pyc','.part'}:continue
        data=p.read_bytes();result[rel.as_posix()]={'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}
    return result
def verify(root:Path,expected:dict,manifest:Path)->dict:
    actual=inventory(root,manifest);missing=[];changed=[]
    for name,record in expected.items():
        if name not in actual:missing.append(name)
        elif actual[name]!=record:changed.append(name)
    added=sorted(set(actual)-set(expected))
    return {'status':'PASS' if not missing and not changed else 'FAIL','checked_files':len(expected),'missing':missing,'changed':changed,'additional_files':added,'meaning':'SHA256 integrity only; not a signature, runtime test, license audit or completeness proof.'}
def main()->int:
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--root',type=Path,default=ROOT);p.add_argument('--manifest',type=Path);p.add_argument('--write',action='store_true');a=p.parse_args();a.root=a.root.resolve();manifest=a.manifest or a.root/'PACK-MANIFEST.json'
    if a.write:
        data={'format':1,'algorithm':'sha256','files':inventory(a.root,manifest)};manifest.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print('Inventory written:',len(data['files']));return 0
    if not manifest.exists():print('Manifest missing',file=sys.stderr);return 2
    data=json.loads(manifest.read_text(encoding='utf-8'));report=verify(a.root,data['files'],manifest);print(json.dumps(report,ensure_ascii=False,indent=2));return 0 if report['status']=='PASS' else 1
if __name__=='__main__':sys.exit(main())
