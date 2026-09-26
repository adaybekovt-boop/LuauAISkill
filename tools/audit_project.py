#!/usr/bin/env python3
"""READ-ONLY heuristic scanner. Findings are review candidates, NOT proof of a bug."""
import argparse,json,re,sys
from pathlib import Path
RULES=[
 ('legacy-scheduler',r'(?<![\w.])(?:wait|spawn|delay)\s*\(','Review task.* migration and changed execution order.'),
 ('remote-code',r'\brequire\s*\(\s*\d','Numeric asset require: establish source, license and full dependency review.'),
 ('dynamic-code',r'\bloadstring\s*\(','Dynamic code execution: review trust boundary; never run untrusted content.'),
 ('lighting-technology',r'\bTechnology\s*=','Review current LightingStyle/PrioritizeLightingQuality and property security.'),
 ('old-ray-query',r'\bFindPartOnRay\w*\s*\(','Review Workspace:Raycast filters, range and semantics.'),
 ('legacy-body-mover',r'Instance\.new\s*\(\s*["\']Body(?:Velocity|Position|Gyro|Force|AngularVelocity)["\']','Review assembly/constraint-based movement; not a blind name replacement.'),
 ('global-environment',r'\b(?:getfenv|setfenv)\s*\(','Review environment mutation and optimization/type-analysis implications.'),
 ('type-escape',r'::\s*any\b','Explain and isolate type escape; it is not runtime validation.'),
 ('unchecked-infinite-loop',r'\bwhile\s+true\s+do\b','Review lifetime, yields, bounded workload and cancellation.'),
 ('scene-wide-scan',r':GetDescendants\s*\(','Review frequency. One-time audit is different from per-frame traversal.'),
 ('remote-invoke-client',r':InvokeClient\s*\(','Server waits on client: review timeout and critical-path trust.'),
 ('animation-owner',r':LoadAnimation\s*\(','Check receiver is intended Animator and asset/rig ownership is correct.'),
]
def scan(root:Path):
 out=[]
 for path in sorted(root.rglob('*')):
  if path.is_symlink() or not path.is_file() or path.suffix.lower() not in ('.lua','.luau'):continue
  if any(x in ('.git','node_modules','vendor') for x in path.parts):continue
  for line_no,line in enumerate(path.read_text(encoding='utf-8',errors='replace').splitlines(),1):
   for name,pattern,advice in RULES:
    if re.search(pattern,line):out.append({'rule':name,'path':path.relative_to(root).as_posix(),'line':line_no,'excerpt':line[:220],'advice':advice,'confidence':'heuristic; includes possible strings/comments'})
 return out
if __name__=='__main__':
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('project',type=Path);args=ap.parse_args()
 if not args.project.is_dir():ap.error('Project directory does not exist')
 print(json.dumps({'read_only':True,'not_a_security_audit':True,'findings':scan(args.project)},ensure_ascii=False,indent=2))
