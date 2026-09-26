#!/usr/bin/env python3
"""Print exact official YAML member blocks after corpus download; no YAML parser needed.
Does not infer undocumented members or inherited signatures. Search base classes next.
"""
import argparse,json,re,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def extract(text:str,member:str):
    lines=text.splitlines();start=None
    for i,line in enumerate(lines):
        if re.match(r'^  - name:\s*'+re.escape(member)+r'\s*$',line):start=i;break
    if start is None:return None
    end=len(lines)
    for i in range(start+1,len(lines)):
        if re.match(r'^  - name:|^[a-z_]+:',lines[i]):end=i;break
    return start+1,end,'\n'.join(lines[start:end])
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('member',help='Lighting.LightingStyle, Workspace:Raycast or class name');p.add_argument('--root',type=Path,default=ROOT/'upstream');args=p.parse_args()
    member=args.member.replace(':','.');classname=member.split('.')[0]
    if not re.fullmatch('[A-Za-z][A-Za-z0-9_]*',classname):p.error('Invalid class name')
    files=sorted(args.root.glob(f'**/reference/engine/classes/{classname}.yaml')) if args.root.exists() else []
    found=False
    for f in files:
        text=f.read_text(encoding='utf-8');block=extract(text,member) if '.' in member else (1,len(text.splitlines()),text)
        if block:
            print(f'\nSOURCE: {f}\nLINES: {block[0]}-{block[1]}\n{block[2]}');found=True
    if found:return 0
    audit=ROOT/'reference'/'lighting-api-audit.json'
    if audit.exists():
        data=json.loads(audit.read_text(encoding='utf-8'))
        for item in data.get('members',[]):
            if item['name']==member:
                print('CURATED METADATA ONLY — not a full class/member reference:')
                print(json.dumps({'source':data['source'],'member':item},ensure_ascii=False,indent=2));return 3
    print('No local exact member block. Download corpus; check base classes and current official index. NOT proof of API absence.',file=sys.stderr);return 2
if __name__=='__main__':sys.exit(main())
