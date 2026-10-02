#!/usr/bin/env python3
"""Check router/TL;DR structure; count cl100k_base tokens when tiktoken is installed.

Without tiktoken report a conservative UTF-8 byte upper bound, never call it a token count.
CI installs the pinned tokenizer so release reports contain actual reproducible token counts.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def inspect(root: Path = ROOT, require_tokenizer: bool = False) -> dict:
    try:
        import tiktoken
        encoder = tiktoken.get_encoding('cl100k_base')
    except ImportError:
        if require_tokenizer:
            raise RuntimeError('Install maintainers/requirements-release.txt for exact token counts')
        encoder = None
    except Exception as error:  # installed, but the encoding file can't be downloaded (offline/proxied CI)
        if require_tokenizer:
            raise RuntimeError(f'tiktoken is installed but cl100k_base could not be loaded: {error}') from error
        encoder = None
    errors = []
    router_lines = len((root / 'SKILL.md').read_text(encoding='utf-8').splitlines())
    if router_lines > 500:
        errors.append(f'SKILL.md: {router_lines} lines > 500')
    chapters = sorted((root / 'handbook').rglob('*.md'))
    for path in chapters:
        lines = path.read_text(encoding='utf-8').splitlines()
        if len(lines) < 9 or lines[2] != '## TL;DR' or not all(x.startswith('- ') for x in lines[3:8]) or lines[8].strip():
            errors.append(f'{path.relative_to(root)}: expected five TL;DR lines after title')
    for path in sorted((root / 'recipes').glob('*/*.md')):
        text = path.read_text(encoding='utf-8')
        prefix = text.split('```luau', 1)[0].split('```lua', 1)[0]
        headings = [line.lower() for line in prefix.splitlines() if line.startswith('## ')]
        if not any('architecture' in line for line in headings):
            errors.append(f'{path.relative_to(root)}: architecture must precede executable code')
        if not any('not' in line and ('use' in line or 'when' in line) for line in headings):
            errors.append(f'{path.relative_to(root)}: when-NOT guidance must precede executable code')
    records = []
    for path in sorted(root.rglob('*')):
        rel = path.relative_to(root)
        if not path.is_file() or set(rel.parts) & {'.git', '.cache', '__pycache__', 'indexes', 'qa'}:
            continue
        if path.suffix not in {'.md', '.py', '.luau', '.json', '.tsv', '.yml', '.txt'}:
            continue
        content = path.read_text(encoding='utf-8')
        count = len(encoder.encode(content, disallowed_special=())) if encoder else len(content.encode('utf-8'))
        generated = rel.as_posix() in {'references/legacy-modernization/CATALOG.md', 'references/legacy-modernization/RANKING.md', 'references/limits.md'}
        knowledge = path.suffix == '.md' and rel.parts[0] in {'handbook', 'tracks', 'recipes', 'references'} and not generated
        if encoder and knowledge and count > 8000:
            errors.append(f'{rel}: authored knowledge exceeds 8000 tokens ({count})')
        records.append({'file': rel.as_posix(), 'tokens' if encoder else 'token_upper_bound_bytes': count,
                        'over_8000': count > 8000})
    return {'tokenizer': 'tiktoken/cl100k_base' if encoder else 'unavailable; UTF-8 byte upper bound only',
            'router_lines': router_lines, 'chapters': len(chapters), 'errors': errors, 'files': records,
            'outliers': [r for r in records if r['over_8000']]}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--require-tokenizer', action='store_true')
    args = parser.parse_args()
    report = inspect(require_tokenizer=args.require_tokenizer)
    target = ROOT / 'qa' / 'content-budget.json'
    target.parent.mkdir(exist_ok=True)
    target.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(f"Router {report['router_lines']}/500 lines; {report['chapters']} chapter summaries; "
          f"{len(report['outliers'])} flagged files; {report['tokenizer']}")
    for error in report['errors']:
        print(error)
    return int(bool(report['errors']))

if __name__ == '__main__':
    raise SystemExit(main())
