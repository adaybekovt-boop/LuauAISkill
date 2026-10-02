#!/usr/bin/env python3
"""Measure bounded legacy-reference candidates in actual pinned official tutorial code.

Samples only Lua/Luau fenced Markdown blocks and .lua/.luau files in creator-docs,
never prose. This current official-documentation corpus is not representative public
code, old tutorials, or model outputs. Results are lexical candidates, not usage telemetry.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import re
from pathlib import Path
import api
import rank_legacy

ROOT = Path(__file__).resolve().parents[1]
DIR = ROOT / 'references' / 'legacy-modernization'
CORPUS = ROOT / '.cache/sources/creator-docs'


def mask_noncode(code: str) -> str:
    """Blank strings/comments, except class-name arguments of actual Instance.new calls."""
    out = list(code)
    class_strings = {m.start(1): (m.start(2), m.end(2)) for m in re.finditer(
        r'\bInstance\.new\s*\(\s*(["\'])([A-Za-z_]\w*)\1', code)}
    i = 0
    while i < len(code):
        start = i
        if code.startswith('--', i):
            i += 2
            long = re.match(r'\[(=*)\[', code[i:])
            if long:
                end_marker = ']' + long.group(1) + ']'
                end = code.find(end_marker, i + len(long.group(0)))
                i = len(code) if end < 0 else end + len(end_marker)
            else:
                end = code.find('\n', i)
                i = len(code) if end < 0 else end
        elif code[i] in '\"\'`':
            quote = code[i]
            i += 1
            while i < len(code):
                if code[i] == '\\':
                    i += 2
                elif code[i] == quote:
                    i += 1
                    break
                else:
                    i += 1
        elif code[i] == '[' and (long := re.match(r'\[(=*)\[', code[i:])):
            end_marker = ']' + long.group(1) + ']'
            end = code.find(end_marker, i + len(long.group(0)))
            i = len(code) if end < 0 else end + len(end_marker)
        else:
            i += 1
            continue
        end = min(i, len(code))
        for n in range(start, end):
            if code[n] != '\n':
                out[n] = ' '
        if start in class_strings and not code.startswith('--', start):
            left, right = class_strings[start]
            out[left:right] = list(code[left:right])
    return ''.join(out)


def fenced_blocks(text: str) -> list[tuple[int, str, str]]:
    result = []
    lines = text.splitlines(keepends=True)
    fence = None
    language = ''
    start = 0
    body = []
    for n, line in enumerate(lines, 1):
        marker = re.match(r'^\s*(`{3,}|~{3,})(.*)$', line)
        if fence is None:
            if marker:
                fence = marker.group(1)
                info = marker.group(2).strip().split()
                language = info[0].lower() if info else ''
                start = n + 1
                body = []
        elif marker and marker.group(1)[0] == fence[0] and len(marker.group(1)) >= len(fence) and not marker.group(2).strip():
            if language in ('lua', 'luau'):
                result.append((start, language, ''.join(body)))
            fence = None
        else:
            body.append(line)
    return result


def build() -> dict:
    lock = json.loads((ROOT / 'sources/lock.json').read_text(encoding='utf-8'))
    source = lock['sources']['creator-docs']
    if not (CORPUS / 'content/en-us').is_dir():
        raise ValueError('Pinned creator-docs corpus is missing; run tools/fetch_sources.py')
    files = sorted(p for p in (CORPUS / 'content/en-us').rglob('*')
                   if p.is_file() and p.suffix in ('.md', '.mdx', '.lua', '.luau'))
    if len(files) > 10000:
        raise ValueError('Safety bound exceeded: more than 10000 source files; review sample scope')
    patterns = [(rank_legacy.identifier(r),
                 re.compile(r'\bInstance\.new\s*\(\s*' + re.escape(rank_legacy.identifier(r)) + r'\b')
                 if r['kind'] == 'class' else rank_legacy.mention_pattern(r))
                for r in api.rows('deprecated.tsv')]
    counts = {name: 0 for name, _ in patterns}
    file_hits = {name: set() for name, _ in patterns}
    receipts = []
    manifest = []
    total_blocks = 0
    code_files = 0
    total_lines = 0
    for path in files:
        raw = path.read_bytes()
        if len(raw) > 4000000:
            raise ValueError(f'File size safety bound exceeded: {path.relative_to(CORPUS)}')
        text = raw.decode('utf-8')
        relative = path.relative_to(CORPUS).as_posix()
        blocks = [(1, path.suffix[1:], text)] if path.suffix in ('.lua', '.luau') else fenced_blocks(text)
        if not blocks:
            continue
        code_files += 1
        file_sha = hashlib.sha256(raw).hexdigest()
        for line, language, code in blocks:
            total_blocks += 1
            total_lines += len(code.splitlines())
            block_sha = hashlib.sha256(code.encode()).hexdigest()
            manifest.append([relative, file_sha, line, language, block_sha])
            cleaned = mask_noncode(code)
            hits = [name for name, pattern in patterns if pattern.search(cleaned)]
            for name in hits:
                counts[name] += 1
                file_hits[name].add(relative)
            if hits:
                receipts.append({'path': relative, 'file_sha256': file_sha, 'first_code_line': line,
                                 'language': language, 'code_sha256': block_sha, 'api_candidates': hits})
    return {
        'schema': 1, 'generated_by': 'tools/sample_legacy_tutorials.py',
        'source': {'kind': 'current pinned official creator-docs tutorial/code sample',
                   'repository': 'https://github.com/Roblox/creator-docs', 'commit': source['sha'],
                   'commit_date': source.get('commit_date', ''), 'scope': 'content/en-us/**/*.md[x] Lua/Luau fences and **/*.lua[u]'},
        'limitations': ['Not a representative public repository or historical tutorial sample.',
                       'Not measured model outputs or error rates.',
                       'Counts are distinct code blocks/files with lexical reference candidates, not runtime usage or independent projects.',
                       'Comments and strings are excluded except Instance.new class literals; backtick interpolation is conservatively omitted.',
                       'Class counts require Instance.new; shared member names need explicit owner text; variable aliases and dynamic indexing may be missed.',
                       'Repeated documentation examples can repeat the same API; examples may intentionally demonstrate old behaviour.'],
        'measurement': {'eligible_source_files': len(files), 'files_with_code': code_files, 'code_blocks': total_blocks,
                        'code_lines': total_lines, 'matching_blocks': len(receipts),
                        'manifest_sha256': hashlib.sha256(json.dumps(manifest, separators=(',', ':')).encode()).hexdigest()},
        'rows': [{'api': name, 'code_block_candidates': counts[name], 'file_candidates': len(file_hits[name])}
                 for name, _ in sorted(patterns, key=lambda item: item[0])],
        'matching_block_receipts': receipts,
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--check', action='store_true')
    args = ap.parse_args()
    sample = build()
    text = json.dumps(sample, indent=1, ensure_ascii=False) + '\n'
    target = DIR / 'tutorial-sample.json'
    if args.check:
        if not target.exists() or target.read_text(encoding='utf-8') != text:
            print('Tutorial sample stale: python tools/sample_legacy_tutorials.py')
            return 1
    else:
        target.write_text(text, encoding='utf-8')
    m = sample['measurement']
    print(f"official tutorial sample: {m['code_blocks']} code blocks in {m['files_with_code']} files; {m['matching_blocks']} lexical candidate blocks; not representative public popularity")
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
