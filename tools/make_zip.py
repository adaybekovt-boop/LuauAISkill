#!/usr/bin/env python3
"""Package local files. Never claims upstream completion merely because a ZIP exists."""
import argparse,hashlib,json,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
EXCLUDE={'.git','__pycache__','.pytest_cache','.toolchain'}
def make(root:Path,out:Path):
 root=root.resolve();out=out.resolve()
 files=[p for p in sorted(root.rglob('*')) if p.is_file() and not p.is_symlink() and p.resolve()!=out and not any(x in EXCLUDE for x in p.relative_to(root).parts) and p.suffix not in ('.pyc','.part')]
 out.parent.mkdir(parents=True,exist_ok=True)
 with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
  for p in files:z.write(p,root.name+'/'+p.relative_to(root).as_posix())
 with zipfile.ZipFile(out) as z:
  bad=z.testzip()
  if bad:raise RuntimeError('ZIP CRC error: '+bad)
 return {'zip':str(out),'files':len(files),'uncompressed_bytes':sum(p.stat().st_size for p in files),'zip_bytes':out.stat().st_size,'sha256':hashlib.sha256(out.read_bytes()).hexdigest()}
if __name__=='__main__':
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--root',type=Path,default=ROOT);ap.add_argument('--out',type=Path,default=ROOT.parent/'LuauAISkill-Expanded.zip');a=ap.parse_args();print(json.dumps(make(a.root,a.out),ensure_ascii=False,indent=2))
