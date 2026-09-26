#!/usr/bin/env python3
"""Download LICENSED official text, with pins, integrity checks and honest coverage.
Python 3.10+, standard library only. Does NOT execute downloaded source code.
Default: pinned Roblox creator-docs English text + Luau website source documents.
--method index uses the official Roblox Markdown indexes instead of its Git tree.
Network access is required. This pack's build environment did not run a live mirror.
"""
from __future__ import annotations
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import sys
import time
from urllib.parse import quote, urljoin, urlparse
from urllib.request import Request, HTTPRedirectHandler, build_opener
from urllib.error import HTTPError, URLError

ROOT = Path(__file__).resolve().parents[1]
PINS = {
    'roblox': {'repo': 'Roblox/creator-docs', 'sha': 'cc850a83d75d8ad7ff638c2733fd3a1a7a0bdd91', 'commit_date': '2026-09-25T10:12:55Z'},
    'luau': {'repo': 'luau-lang/site', 'sha': '07c3dcd990e170cce92bae9027e16c1377de5fb4', 'commit_date': '2026-09-21T10:17:32Z'},
}
ALLOWED_HOSTS = {'api.github.com', 'raw.githubusercontent.com', 'create.roblox.com'}
TEXT_EXTENSIONS = {'.md', '.mdx', '.yaml', '.yml', '.json', '.txt', '.lua', '.luau'}
MAX_BYTES = 32 * 1024 * 1024

def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()

def checked_url(url: str) -> str:
    parsed = urlparse(url)
    if parsed.scheme != 'https' or parsed.hostname not in ALLOWED_HOSTS or parsed.username or parsed.password:
        raise ValueError('URL is outside the official HTTPS allowlist')
    if parsed.port not in (None, 443):
        raise ValueError('Unexpected port')
    return url

class SafeRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        checked_url(newurl)  # Validate BEFORE following a redirect, not afterwards.
        redirected = super().redirect_request(req, fp, code, msg, headers, newurl)
        if redirected is not None and urlparse(newurl).hostname != urlparse(req.full_url).hostname:
            redirected.remove_header('Authorization')
        return redirected

def safe_path(root: Path, relative: str) -> Path:
    if '\\' in relative or '\x00' in relative:
        raise ValueError('Unsafe path')
    p = PurePosixPath(relative)
    if not relative or not p.parts or p.is_absolute() or '..' in p.parts or ':' in relative:
        raise ValueError('Unsafe relative path')
    target = (root / Path(*p.parts)).resolve()
    if not target.is_relative_to(root.resolve()):
        raise ValueError('Path escapes destination')
    return target

def git_blob_sha(data: bytes) -> str:
    return hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()

def atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + '.part')
    try:
        tmp.write_bytes(data)
        os.replace(tmp, path)
    finally:
        if tmp.exists():
            tmp.unlink()

def write_json(path: Path, data: object) -> None:
    atomic_write(path, (json.dumps(data, ensure_ascii=False, indent=2) + '\n').encode())

def fetch(url: str, attempts: int = 4, limit: int = MAX_BYTES) -> bytes:
    """Bounded GET. Token is sent to the GitHub API ONLY, never to raw/site hosts."""
    checked_url(url)
    headers = {'User-Agent': 'TK-Luau-Knowledge-Mirror/1.0', 'Accept': '*/*'}
    token = os.environ.get('GITHUB_TOKEN')
    if urlparse(url).hostname == 'api.github.com':
        headers['Accept'] = 'application/vnd.github+json'
        if token:
            headers['Authorization'] = 'Bearer ' + token
    last: Exception | None = None
    for attempt in range(attempts):
        try:
            with build_opener(SafeRedirect()).open(Request(url, headers=headers), timeout=45) as response:
                checked_url(response.geturl())
                data = response.read(limit + 1)
                if len(data) > limit:
                    raise ValueError('Response exceeds configured size limit')
                return data
        except HTTPError as e:
            last = e
            if e.code not in (408, 429, 500, 502, 503, 504):
                raise
            delay = min(30, 2 ** attempt)
            retry_after = e.headers.get('Retry-After', '')
            if retry_after.isdigit():
                delay = min(60, int(retry_after))
        except (URLError, TimeoutError, OSError) as e:
            last = e
            delay = min(30, 2 ** attempt)
        if attempt + 1 < attempts:
            time.sleep(delay)
    raise RuntimeError(f'GET failed after {attempts} attempts: {type(last).__name__}') from last

def get_json(url: str) -> dict:
    value = json.loads(fetch(url))
    if not isinstance(value, dict):
        raise ValueError('Expected JSON object')
    if 'message' in value and 'documentation_url' in value:
        raise ValueError('GitHub returned an API error')
    return value

def enumerate_tree(repo: str, sha: str) -> list[dict]:
    base = f'https://api.github.com/repos/{repo}/git/trees/'
    data = get_json(base + sha + '?recursive=1')
    if not data.get('truncated', False):
        if 'tree' not in data:
            raise ValueError('Missing tree in API response')
        return data['tree']
    # A truncated response is NOT complete. Walk individual directory trees.
    output: list[dict] = []
    pending = [('', sha)]
    while pending:
        prefix, tree_sha = pending.pop()
        node = get_json(base + tree_sha)
        if node.get('truncated') or 'tree' not in node:
            raise RuntimeError('Nonrecursive tree was truncated/incomplete; refusing COMPLETE')
        for entry in node['tree']:
            full = prefix + entry['path']
            item = dict(entry, path=full)
            output.append(item)
            if entry['type'] == 'tree':
                pending.append((full + '/', entry['sha']))
    return output

def selected(key: str, entry: dict) -> bool:
    if entry.get('type') != 'blob' or entry.get('mode') == '120000':
        return False
    path = entry['path']
    name = PurePosixPath(path).name
    if '/' not in path and (name.upper().startswith(('LICENSE', 'COPYING', 'NOTICE')) or name == 'README.md'):
        return True
    if key == 'roblox':
        return path.startswith('content/en-us/') and PurePosixPath(path).suffix.lower() in TEXT_EXTENSIONS
    # Luau source website: documentation and posts, not build caches or vendor code.
    if any(part in {'node_modules', '.git', 'dist', 'vendor'} for part in PurePosixPath(path).parts):
        return False
    return PurePosixPath(path).suffix.lower() in {'.md', '.mdx', '.lua', '.luau'}

def resolve_pin(key: str, latest: bool) -> dict:
    pin = dict(PINS[key])
    if latest:
        metadata = get_json(f'https://api.github.com/repos/{pin["repo"]}')
        branch = metadata['default_branch']
        commit = get_json(f'https://api.github.com/repos/{pin["repo"]}/commits/{quote(branch, safe="")}')
        pin['sha'] = commit['sha']
        pin['commit_date'] = commit['commit']['committer']['date']
    return pin

def mirror_repo(key: str, destination: Path, workers: int, latest: bool) -> dict:
    pin = resolve_pin(key, latest)
    repo, sha = pin['repo'], pin['sha']
    folder = destination / f'{repo.replace("/", "__")}__{sha[:12]}'
    folder.mkdir(parents=True, exist_ok=True)
    entries = enumerate_tree(repo, sha)
    targets = [e for e in entries if selected(key, e)]
    if not targets or not any(PurePosixPath(e['path']).name.upper().startswith(('LICENSE', 'COPYING')) for e in targets):
        raise RuntimeError('No documents or no license found; refusing unlicensed/empty mirror')
    records: list[dict] = []
    errors: list[dict] = []
    def download(entry: dict) -> dict:
        path = entry['path']
        target = safe_path(folder, path)
        raw = f'https://raw.githubusercontent.com/{repo}/{sha}/{quote(path, safe="/")}'
        data = target.read_bytes() if target.is_file() and target.stat().st_size <= MAX_BYTES else b''
        reused = bool(data and git_blob_sha(data) == entry['sha'])
        if not reused:
            data = fetch(raw)
            if git_blob_sha(data) != entry['sha']:
                raise ValueError('Git blob SHA mismatch')
        data.decode('utf-8')
        if data.startswith(b'version https://git-lfs.github.com/spec/v1'):
            raise ValueError('LFS pointer is not the referenced document')
        if not reused:
            atomic_write(target, data)
        return {'path': path, 'url': raw, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(), 'git_blob_sha': entry['sha'], 'reused_verified_file': reused}
    # Download license files before content. Failure stops this repository.
    license_entries = [e for e in targets if '/' not in e['path'] and PurePosixPath(e['path']).name.upper().startswith(('LICENSE', 'COPYING', 'NOTICE'))]
    for entry in license_entries:
        records.append(download(entry))
    remaining = [e for e in targets if e not in license_entries]
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {pool.submit(download, e): e for e in remaining}
        for index, future in enumerate(as_completed(futures), 1):
            entry = futures[future]
            try:
                records.append(future.result())
            except Exception as e:
                errors.append({'path': entry['path'], 'error': type(e).__name__, 'detail': str(e)[:240]})
            if index % 100 == 0:
                print(f'{repo}: processed {index}/{len(remaining)}, errors={len(errors)}', flush=True)
    result = {'source': key, **pin, 'method': 'github-tree-raw', 'fetched_at_utc': utc_now(), 'expected_files': len(targets), 'saved_files': len(records), 'complete': not errors and len(records) == len(targets), 'media_included': False, 'files': sorted(records, key=lambda r:r['path']), 'errors': errors}
    write_json(folder / 'MIRROR-MANIFEST.json', result)
    return {k:v for k,v in result.items() if k != 'files'}

def index_links(text: str) -> list[str]:
    links = set()
    for match in re.finditer(r'\]\(([^\s)]+)\)', text):
        url = urljoin('https://create.roblox.com', match.group(1).split('#')[0])
        p = urlparse(url)
        if p.scheme == 'https' and p.netloc == 'create.roblox.com' and p.path.startswith('/docs/') and p.path.endswith('.md') and not p.query:
            links.add(url)
    return sorted(links)

def mirror_index(destination: Path, workers: int) -> dict:
    """Website is mutable: timestamps/hashes are recorded, NOT presented as a commit snapshot."""
    folder = destination / 'Roblox__website'
    folder.mkdir(parents=True, exist_ok=True)
    # License attribution accompanies redistributed website text.
    pin = PINS['roblox']
    for name in ('LICENSE', 'LICENSE-CODE'):
        url = f'https://raw.githubusercontent.com/{pin["repo"]}/{pin["sha"]}/{name}'
        atomic_write(folder / name, fetch(url))
    urls: set[str] = set()
    for url in ('https://create.roblox.com/docs/llms.txt', 'https://create.roblox.com/docs/reference/engine/llms.txt', 'https://create.roblox.com/docs/cloud/llms.txt'):
        data = fetch(url)
        text = data.decode('utf-8')
        if text.lstrip().lower().startswith(('<!doctype', '<html')):
            raise ValueError('Index returned HTML rather than text')
        atomic_write(safe_path(folder, urlparse(url).path.lstrip('/')), data)
        urls.update(index_links(text))
    if not urls:
        raise RuntimeError('Indexes returned no Markdown URLs')
    files, errors = [], []
    def one(url: str) -> dict:
        data = fetch(url)
        text = data.decode('utf-8')
        if text.lstrip().lower().startswith(('<!doctype', '<html')):
            raise ValueError('Markdown endpoint returned an HTML page')
        path = urlparse(url).path.lstrip('/')
        atomic_write(safe_path(folder, path), data)
        return {'path':path, 'url':url, 'bytes':len(data), 'sha256':hashlib.sha256(data).hexdigest()}
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {pool.submit(one,url):url for url in sorted(urls)}
        for index,future in enumerate(as_completed(futures),1):
            try:
                files.append(future.result())
            except Exception as e:
                errors.append({'url':futures[future], 'error':type(e).__name__, 'detail':str(e)[:240]})
            if index % 100 == 0:
                print(f'Roblox website: {index}/{len(urls)} pages, errors={len(errors)}', flush=True)
    result={'source':'roblox','method':'official-markdown-indexes','fetched_at_utc':utc_now(),'pinned':False,'expected_pages':len(urls),'saved_pages':len(files),'complete':not errors and len(files)==len(urls),'media_included':False,'files':sorted(files,key=lambda r:r['path']),'errors':errors}
    write_json(folder/'MIRROR-MANIFEST.json',result)
    return {k:v for k,v in result.items() if k!='files'}

def main() -> int:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--only', choices=('all','roblox','luau'), default='all')
    parser.add_argument('--latest', action='store_true', help='Resolve latest repository SHA instead of reproducible September pins')
    parser.add_argument('--method', choices=('github','index'), default='github', help='Roblox download method; Luau always uses GitHub')
    parser.add_argument('--destination',type=Path, default=ROOT/'upstream')
    parser.add_argument('--workers', type=int, default=4)
    args=parser.parse_args()
    if not 1 <= args.workers <= 8:
        parser.error('--workers must be in 1..8')
    args.destination.mkdir(parents=True,exist_ok=True)
    results=[]
    for key in ('roblox','luau'):
        if args.only not in ('all',key):
            continue
        print('Downloading official text:',key,flush=True)
        try:
            result=mirror_index(args.destination,args.workers) if key=='roblox' and args.method=='index' else mirror_repo(key,args.destination,args.workers,args.latest)
        except Exception as e:
            result={'source':key,'complete':False,'error':type(e).__name__,'detail':str(e)[:500]}
        results.append(result)
        print(json.dumps(result,ensure_ascii=False),flush=True)
    complete=bool(results) and all(r.get('complete') for r in results)
    report={'created_at_utc':utc_now(),'requested':args.only,'complete_for_requested_sources':complete,'corpora':results}
    write_json(args.destination/'DOWNLOAD-REPORT.json',report)
    print('COMPLETE' if complete else 'INCOMPLETE — inspect DOWNLOAD-REPORT.json; no completeness claim is valid.')
    return 0 if complete else 1
if __name__=='__main__':
    sys.exit(main())
