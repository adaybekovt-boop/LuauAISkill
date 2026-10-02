#!/usr/bin/env python3
"""Recheck authored references against fetched snapshot and list potentially affected files."""
from __future__ import annotations
import csv
import io
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def changed_api_terms() -> set[str]:
    terms = set()
    for path in sorted((ROOT / 'api').glob('*.tsv')):
        old = subprocess.run(['git', 'show', f'HEAD:api/{path.name}'], cwd=ROOT,
                             capture_output=True, text=True, check=True).stdout
        new = path.read_text(encoding='utf-8')
        old_rows = set(old.splitlines()[1:])
        new_rows = set(new.splitlines()[1:])
        for line in old_rows ^ new_rows:
            cells = next(csv.reader(io.StringIO(line), delimiter='\t'))
            # Include qualified identities and their owner/member components conservatively.
            for cell in cells[:3]:
                if cell and len(cell) > 2:
                    terms.add(cell)
    return terms


def main() -> int:
    checks = []
    for tool, args in [('check_api_refs.py', []), ('check_sources.py', ['--check']),
                       ('check_facts.py', [])]:
        result = subprocess.run([sys.executable, str(ROOT / 'tools' / tool), *args], cwd=ROOT,
                                capture_output=True, text=True)
        checks.append({'command': f'python tools/{tool} ' + ' '.join(args),
                       'returncode': result.returncode, 'output': result.stdout + result.stderr})
    terms = changed_api_terms()
    affected = []
    for path in sorted(ROOT.rglob('*')):
        rel = path.relative_to(ROOT)
        if not path.is_file() or set(rel.parts) & {'.git', '.cache', 'api', 'qa', 'indexes'}:
            continue
        if path.suffix not in {'.md', '.luau', '.json'} or path.name == 'registry.json':
            continue
        content = path.read_text(encoding='utf-8')
        if any(term in content for term in terms) or any(rel.as_posix() in c['output'] for c in checks if c['returncode']):
            affected.append(rel.as_posix())
    report = {'checks': checks, 'affected_files': affected,
              'meaning': 'Conservative dependency candidates; review, not proof that every file is broken.'}
    (ROOT / 'qa').mkdir(exist_ok=True)
    (ROOT / 'qa' / 'freshness.json').write_text(json.dumps(report, indent=2) + '\n')
    print('## Snapshot validation\n')
    for check in checks:
        print(f"### {check['command'].strip()}: {'PASS' if check['returncode'] == 0 else 'FAIL'}\n")
        print('```text\n' + check['output'][-12000:] + '\n```\n')
    print('## Potentially affected files\n')
    print('\n'.join('- ' + path for path in affected) or 'None identified.')
    print('\n' + report['meaning'])
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
