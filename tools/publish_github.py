#!/usr/bin/env python3
"""Publish the verified pack to the one repository selected by its owner.
No tokens are collected. Uses the locally installed Git credential manager or
an already authenticated GitHub CLI. Never force pushes or deletes remote files.
Only files in PACK-MANIFEST.json are eligible. Network operation is NOT performed
by --dry-run. First publication into an empty repository targets main. Existing
repositories receive a new branch; differing existing files are refused.
"""
from __future__ import annotations
import argparse, hashlib, json, shutil, subprocess, sys, tempfile
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
ROOT=Path(__file__).resolve().parents[1]
REPOSITORY='adaybekovt-boop/LuauAISkill'
REMOTE='https://github.com/'+REPOSITORY+'.git'
MAX_FILE=95*1024*1024
class PublishError(RuntimeError): pass

def verified_files(root:Path)->list[Path]:
    root=root.resolve(); manifest=root/'PACK-MANIFEST.json'
    if not manifest.is_file() or manifest.is_symlink():
        raise PublishError('Missing regular PACK-MANIFEST.json; run tools/release_pack.py first.')
    obj=json.loads(manifest.read_text(encoding='utf-8'))
    if obj.get('format')!=1 or obj.get('algorithm')!='sha256' or not isinstance(obj.get('files'),dict):
        raise PublishError('Unsupported inventory format')
    result=[]
    for name,entry in obj['files'].items():
        q=PurePosixPath(name)
        if not name or q.is_absolute() or '..' in q.parts or '\\' in name or ':' in name or '\x00' in name:
            raise PublishError('Unsafe inventory path: '+name)
        if any(x in {'.git','.ssh','__pycache__'} or x.lower()=='.env' or x.lower().startswith('.env.') for x in q.parts):
            raise PublishError('Sensitive/cache path refused: '+name)
        p=root.joinpath(*q.parts)
        # Refuse symlinks in ANY path component, not only the final filename.
        if any((root.joinpath(*q.parts[:i])).is_symlink() for i in range(1,len(q.parts)+1)):
            raise PublishError('Symlink refused: '+name)
        if not p.resolve().is_relative_to(root) or not p.is_file():
            raise PublishError('Missing or escaped file: '+name)
        if p.stat().st_size>MAX_FILE: raise PublishError('File too large for normal Git: '+name)
        data=p.read_bytes()
        if entry.get('bytes')!=len(data) or entry.get('sha256')!=hashlib.sha256(data).hexdigest():
            raise PublishError('Inventory mismatch: '+name+'; rebuild only after reviewing the change.')
        result.append(p)
    if not result:raise PublishError('Empty pack refused')
    return result+[manifest]

def git_command(args:list[str],cwd:Path,helper:bool=False,capture:bool=True)->subprocess.CompletedProcess:
    prefix=['git']
    if helper:
        prefix+=['-c','credential.helper=','-c','credential.helper=!gh auth git-credential']
    p=subprocess.run(prefix+args,cwd=cwd,text=True,encoding='utf-8',errors='replace',capture_output=capture)
    if p.returncode:
        # Git commands never receive a token/password in argv. Do not print env.
        raise PublishError('Git failed: '+' '.join(args[:2])+('\n'+(p.stderr or '')[-3000:] if capture else ''))
    return p

def install_files(root:Path,checkout:Path,paths:list[Path])->list[str]:
    changes=[]
    for src in paths:
        rel=src.relative_to(root);dest=checkout/rel
        if any(checkout.joinpath(*rel.parts[:i]).is_symlink() for i in range(1,len(rel.parts)+1)):
            raise PublishError('Remote checkout has symlink at '+rel.as_posix())
        if not dest.resolve().is_relative_to(checkout.resolve()):raise PublishError('Escaped checkout path')
        if dest.exists():
            if not dest.is_file() or dest.read_bytes()!=src.read_bytes():
                raise PublishError('Existing file differs: '+rel.as_posix()+'. No files have been pushed. Review/update manually.')
        else:changes.append(rel.as_posix())
    # Preflight EVERY destination before copying any files.
    for src in paths:
        dest=checkout/src.relative_to(root);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dest)
    return changes

def main()->int:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dry-run',action='store_true')
    a=parser.parse_args()
    try:
        paths=verified_files(ROOT)
        print('Destination:',REPOSITORY)
        print('Verified files:',len(paths),'bytes:',sum(p.stat().st_size for p in paths))
        if a.dry_run:
            print('DRY RUN: no authentication, network, commits or push attempted.');return 0
        if not shutil.which('git'):raise PublishError('Install Git for your operating system, then run again.')
        helper=False
        if shutil.which('gh'):
            helper=subprocess.run(['gh','auth','status','--hostname','github.com'],capture_output=True).returncode==0
        print('Authentication: existing GitHub CLI session' if helper else 'Authentication: your local Git credential manager')
        with tempfile.TemporaryDirectory(prefix='luau-skill-publish-') as temp:
            base=Path(temp);checkout=base/'repo'
            refs=git_command(['ls-remote','--heads',REMOTE],base,helper).stdout.strip()
            git_command(['clone','--',REMOTE,str(checkout)],base,helper,capture=False)
            empty=not refs
            branch='main' if empty else 'skill/knowledge-pack-'+datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S')
            git_command(['checkout','--orphan',branch] if empty else ['checkout','-b',branch],checkout,helper)
            changed=install_files(ROOT,checkout,paths)
            if not changed:
                print('Remote already contains the same files; nothing pushed.');return 0
            # This is a newly cloned isolated directory with only verified pack files added.
            git_command(['add','--all','--','.'],checkout,helper)
            git_command(['-c','user.name=LuauAISkill Import','-c','user.email=noreply@users.noreply.github.com',
                         'commit','-m','Add source-grounded Luau Roblox AI skill and reproducible corpus builder'],checkout,helper)
            git_command(['push','origin','HEAD:refs/heads/'+branch],checkout,helper,capture=False)
            local=git_command(['rev-parse','HEAD'],checkout,helper).stdout.strip()
            remote=git_command(['ls-remote',REMOTE,'refs/heads/'+branch],checkout,helper).stdout.split()
            if not remote or remote[0]!=local:raise PublishError('Push returned, but remote SHA verification failed.')
            print('PUBLISHED and remote SHA verified:',local)
            print('https://github.com/'+REPOSITORY+'/tree/'+branch)
            if not empty:print('Published to a NEW BRANCH. Existing default branch was not changed.')
        return 0
    except (PublishError,OSError,ValueError,KeyError) as e:
        print('PUBLICATION NOT CONFIRMED:',e,file=sys.stderr);return 1
if __name__=='__main__':sys.exit(main())
