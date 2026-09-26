#!/usr/bin/env python3
"""Build a local FTS5 index. Python 3.10+, standard library. Never runs indexed code."""
from __future__ import annotations
import argparse, hashlib, json, os, sqlite3
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
EXTS={'.md','.mdx','.txt','.yaml','.yml','.luau','.lua'}
SKIP={'qa','tests','evals','tools','.git','.github','__pycache__','node_modules','indexes','.toolchain','roblox-api'}

def chunks(text: str, target: int=70):
    lines=text.splitlines(); start=0; fence=False
    for i,line in enumerate(lines):
        if line.lstrip().startswith(('```','~~~')):
            fence=not fence
        size=i-start+1
        boundary=(not fence and size>=target and not line.strip()) or size>=240
        if boundary:
            yield start+1,i+1,'\n'.join(lines[start:i+1])
            start=i+1
    if start<len(lines):
        yield start+1,len(lines),'\n'.join(lines[start:])

def candidates(root: Path):
    for p in sorted(root.rglob('*')):
        if not p.is_file() or p.is_symlink() or p.suffix.lower() not in EXTS:
            continue
        rel=p.relative_to(root)
        if any(part in SKIP for part in rel.parts):
            continue
        if rel.as_posix().startswith('sources/INDEXED-ONLY'):
            continue
        yield p

def build(root: Path, destination: Path) -> dict:
    root=root.resolve(); destination.parent.mkdir(parents=True,exist_ok=True)
    tmp=destination.with_suffix('.tmp.sqlite'); tmp.unlink(missing_ok=True)
    conn=sqlite3.connect(tmp)
    try:
        conn.execute('CREATE VIRTUAL TABLE chunks USING fts5(path UNINDEXED, start UNINDEXED, end UNINDEXED, title, body, tokenize="unicode61")')
        conn.execute('CREATE TABLE files(path TEXT PRIMARY KEY, sha256 TEXT, lines INTEGER)')
        count=0; file_count=0
        for path in candidates(root):
            data=path.read_bytes()
            try: text=data.decode('utf-8')
            except UnicodeDecodeError: continue
            rel=path.relative_to(root).as_posix()
            title=next((x.lstrip('# ').strip() for x in text.splitlines() if x.startswith('# ')),path.stem)
            conn.execute('INSERT INTO files VALUES(?,?,?)',(rel,hashlib.sha256(data).hexdigest(),len(text.splitlines())))
            file_count+=1
            for begin,end,body in chunks(text):
                if body.strip():
                    conn.execute('INSERT INTO chunks VALUES(?,?,?,?,?)',(rel,begin,end,title,body)); count+=1
        conn.execute('CREATE TABLE metadata(key TEXT PRIMARY KEY, value TEXT)')
        conn.execute('INSERT INTO metadata VALUES(?,?)',('format','1'))
        conn.commit()
    finally: conn.close()
    os.replace(tmp,destination)
    return {'indexed_files':file_count,'chunks':count,'database':str(destination),'note':'Index count is not upstream coverage. Read upstream/DOWNLOAD-REPORT.json for mirror status.'}

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--root',type=Path,default=ROOT);ap.add_argument('--output',type=Path)
    args=ap.parse_args(); print(json.dumps(build(args.root,args.output or args.root/'indexes'/'knowledge.sqlite'),ensure_ascii=False,indent=2))
if __name__=='__main__':main()
