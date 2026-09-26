#!/usr/bin/env python3
"""Run available target Luau tools. Missing tools are NOT_RUN, never PASS.
The CLI runtime has no Roblox DataModel: only pure.spec.luau is executable here.
Compiler acceptance of Roblox files does not validate Engine API/type bindings.
"""
from __future__ import annotations
import argparse,json,shutil,subprocess,sys
from datetime import datetime,timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def run(command:list[str],cwd:Path,timeout:int=60)->dict:
    try:
        p=subprocess.run(command,cwd=cwd,text=True,encoding='utf-8',errors='replace',capture_output=True,timeout=timeout)
        return {'command':command,'status':'PASS' if p.returncode==0 else 'FAIL','exit_code':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
    except subprocess.TimeoutExpired:
        return {'command':command,'status':'FAIL','reason':'TIMEOUT'}
    except OSError as e:
        return {'command':command,'status':'FAIL','reason':str(e)}
def validate(root:Path,compiler:str|None,runtime:str|None,probes:bool)->dict:
    compiler=shutil.which(compiler) if compiler else shutil.which('luau-compile')
    runtime=shutil.which(runtime) if runtime else shutil.which('luau')
    records=[]
    paths=[p for p in sorted((root/'examples').rglob('*.luau')) if probes or 'feature-probes' not in p.parts]
    if compiler:
        for path in paths:
            record=run([compiler,str(path)],root);record['kind']='syntax_compile';record['path']=path.relative_to(root).as_posix();records.append(record)
    else:
        records.append({'kind':'syntax_compile','status':'NOT_RUN','reason':'luau-compile not available','selected_files':len(paths)})
    if runtime:
        record=run([runtime,'examples/tests/pure.spec.luau'],root);record['kind']='pure_runtime_tests';records.append(record)
    else:
        records.append({'kind':'pure_runtime_tests','status':'NOT_RUN','reason':'standalone luau runtime not available'})
    records.append({'kind':'roblox_studio','status':'NOT_RUN','reason':'This runner does not launch or emulate Roblox Studio'})
    return {'created_at_utc':datetime.now(timezone.utc).isoformat(),'tool_paths':{'compiler':compiler,'runtime':runtime},'feature_probes_included':probes,'records':records,'note':'Only executed commands may be PASS. Runtime tests do not cover Roblox services, replication, visuals or target devices.'}
def main()->int:
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--compiler');p.add_argument('--runtime');p.add_argument('--include-probes',action='store_true');p.add_argument('--output',type=Path,default=ROOT/'qa'/'EXAMPLE-CHECKS.json');a=p.parse_args()
    report=validate(ROOT,a.compiler,a.runtime,a.include_probes);a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print(json.dumps(report,ensure_ascii=False,indent=2))
    if any(x['status']=='FAIL' for x in report['records']):return 1
    if any(x['status']=='NOT_RUN' for x in report['records'] if x['kind']!='roblox_studio'):return 2
    return 0
if __name__=='__main__':sys.exit(main())
