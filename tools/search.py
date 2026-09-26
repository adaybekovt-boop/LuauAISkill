#!/usr/bin/env python3
"""Local keyword search; results are pointers, not complete API evidence."""
from __future__ import annotations
import argparse, hashlib, json, re, sqlite3, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SYNONYMS={'освещение':['lighting','LightingStyle'],'свет':['lighting','shadows'],'графика':['graphics','PBR'],'сохранения':['DataStore','UpdateAsync'],'сеть':['remote','replication'],'типизация':['types','strict'],'ходьба':['animation','character'],'звук':['audio','Wire'],'память':['memory','cleanup'],'многопоточность':['Actor','parallel'],'частицы':['particles'],'покупки':['purchasing','receipt'],'интерфейс':['UI','styling'],'стриминг':['streaming','SLIM']}

def terms(query: str) -> list[str]:
    values=re.findall(r'[\w]+',query,flags=re.UNICODE)
    if len(values)>24:values=values[:24]
    expanded=list(values)
    for value in values:expanded.extend(SYNONYMS.get(value.lower(),[]))
    return list(dict.fromkeys(expanded))

def search(db: Path, query: str, limit: int=8, root:Path=ROOT) -> list[dict]:
    words=terms(query)
    if not words:return []
    expression=' OR '.join('"'+w.replace('"','""')+'"' for w in words)
    uri=db.resolve().as_uri()+'?mode=ro';conn=sqlite3.connect(uri,uri=True)
    try:
        rows=conn.execute('SELECT path,start,end,title,snippet(chunks,4,"[", "]", " … ",36),bm25(chunks,0,0,0,4,1) FROM chunks WHERE chunks MATCH ? ORDER BY 6 LIMIT ?',(expression,limit)).fetchall()
        result=[]
        for path,start,end,title,snippet,rank in rows:
            source=root/path
            expected=conn.execute('SELECT sha256 FROM files WHERE path=?',(path,)).fetchone()
            stale=not source.is_file() or hashlib.sha256(source.read_bytes()).hexdigest()!=expected[0]
            result.append({'path':path,'start_line':int(start),'end_line':int(end),'title':title,'snippet':snippet,'stale_index':stale,'rank':rank})
        return result
    finally:conn.close()

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('query');ap.add_argument('--limit',type=int,default=8);ap.add_argument('--json',action='store_true');ap.add_argument('--db',type=Path,default=ROOT/'indexes'/'knowledge.sqlite')
    args=ap.parse_args()
    if not args.db.exists():
        print('No index. Run: python tools/build_index.py',file=sys.stderr);return 2
    if not 1<=args.limit<=50:ap.error('--limit must be 1..50')
    try: results=search(args.db,args.query,args.limit)
    except sqlite3.Error as e: print('Index error:',e,file=sys.stderr);return 2
    if args.json:print(json.dumps(results,ensure_ascii=False,indent=2))
    else:
        for r in results:
            print(f'\n{r["path"]}:{r["start_line"]}-{r["end_line"]} — {r["title"]}'+(' [STALE: rebuild index]' if r['stale_index'] else ''))
            print(r['snippet'])
        if not results:print('No match in LOCAL indexed content. This does not prove the API/topic is absent.')
    return 0
if __name__=='__main__':sys.exit(main())
