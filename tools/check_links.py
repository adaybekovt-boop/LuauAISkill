#!/usr/bin/env python3
"""Check file targets of authored Markdown links. Not a live URL/anchor checker.
Upstream source links retain their original layout; missing media in a text-only
mirror is not a reason to rewrite official source documents.
"""
from __future__ import annotations
import argparse,json,re,sys
from pathlib import Path
from urllib.parse import unquote,urlsplit
ROOT=Path(__file__).resolve().parents[1]
SKIP={'.git','upstream','indexes','__pycache__'}
def check(root:Path)->dict:
    root=root.resolve();missing=[];checked=0;outside=[]
    for p in sorted(root.rglob('*.md')):
        if any(s in SKIP for s in p.relative_to(root).parts):continue
        text=p.read_text(encoding='utf-8')
        for m in re.finditer(r'(?<!!)\[[^\]\n]+\]\(([^\s)]+)(?:\s+"[^"]*")?\)',text):
            target=m.group(1).strip('<>');parsed=urlsplit(target)
            if parsed.scheme or parsed.netloc or not parsed.path:continue
            # Leading-slash web paths are not local package references.
            if parsed.path.startswith('/'):continue
            dest=(p.parent/unquote(parsed.path)).resolve();checked+=1
            record={'file':p.relative_to(root).as_posix(),'line':text.count('\n',0,m.start())+1,'target':target}
            if not dest.is_relative_to(root):outside.append(record)
            elif not dest.exists():missing.append(record)
    return {'status':'PASS' if not missing and not outside else 'FAIL','checked_file_links':checked,'missing':missing,'outside_root':outside,'scope':'Authored relative Markdown file links only; not anchors or online URL availability.'}
def main()->int:
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--root',type=Path,default=ROOT);a=ap.parse_args()
    r=check(a.root);print(json.dumps(r,ensure_ascii=False,indent=2));return 0 if r['status']=='PASS' else 1
if __name__=='__main__':sys.exit(main())
