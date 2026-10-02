#!/usr/bin/env python3
"""Reproduce an editorial-priority ranking of all pinned deprecated/superseded API rows.

This is not a popularity or model-error benchmark. Public-code frequency was not sampled.
Exact identifier mentions in repository eval prompts/fixtures are a local relevance signal.
The independent, explicit risk map is in references/legacy-modernization/ranking-policy.json.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import re
from pathlib import Path
import api

ROOT = Path(__file__).resolve().parents[1]
DIR = ROOT / 'references' / 'legacy-modernization'


def identifier(row: dict) -> str:
    if row['kind'] in ('global', 'datatype', 'library'):
        return row['member'].replace(':', '.')
    return f"{row['owner']}.{row['member']}".rstrip('.')


def eval_corpus() -> list[tuple[str, str]]:
    cases = []
    for path in sorted((ROOT / 'evals' / 'cases').glob('*.jsonl')):
        for line in path.read_text(encoding='utf-8').splitlines():
            case = json.loads(line)
            text = case['prompt']
            if case.get('fixture'):
                text += '\n' + (ROOT / case['fixture']).read_text(encoding='utf-8')
            cases.append((case['id'], text))
    return cases


def mention_pattern(row: dict) -> re.Pattern:
    name = identifier(row)
    if row['kind'] == 'global':
        return re.compile(r'(?<![\w.:])' + re.escape(name) + r'(?![\w])')
    if row['kind'] in ('class', 'EnumItem', 'datatype', 'library'):
        return re.compile(r'(?<![\w])' + re.escape(name).replace(r'\.', r'[.:]') + r'(?![\w])')
    # Shared names such as Transparency or LoadAnimation need an explicit owner.
    # A bare member mention cannot establish which receiver the prompt intends.
    owners = [owner for owner, ms in api.members().items() if row['member'] in ms]
    if len(owners) > 1:
        return re.compile(r'(?<![\w])' + re.escape(row['owner']) + r'[.:]' +
                          re.escape(row['member']) + r'(?![\w])', re.IGNORECASE)
    return re.compile(r'[.:]' + re.escape(row['member']) + r'(?![\w])')


def accessibility(row: dict) -> str:
    if row['kind'] == 'class':
        flags = api.classes().get(row['owner'], {}).get('tags', '')
        return 'restricted_or_undocumented' if 'undocumented' in flags else 'documented'
    found = api.resolve_member(row['owner'], row['member'])
    if not found:
        return 'documented'
    _, member = found
    flags = member['flags']
    return ('restricted_or_undocumented' if member['read'] != 'None' or 'undocumented' in flags or
            'call:plugin-only' in flags or 'notscriptable' in flags else 'documented')


def build() -> dict:
    policy = json.loads((DIR / 'ranking-policy.json').read_text(encoding='utf-8'))
    corpus = eval_corpus()
    sample_path = DIR / 'tutorial-sample.json'
    sample = json.loads(sample_path.read_text(encoding='utf-8')) if sample_path.exists() else None
    sample_counts = {r['api']: r['code_block_candidates'] for r in sample['rows']} if sample else {}
    rows = []
    for row in api.rows('deprecated.tsv'):
        name = identifier(row)
        group = next(g for g in policy['risk_groups'] if re.search(g['match'], name))
        hits = [case_id for case_id, text in corpus if mention_pattern(row).search(text)]
        available = accessibility(row)
        # Risk is a declared editorial judgement. Exact mentions are observed, but neither is measured AI frequency.
        score = min(len(hits), 5) * 20 + group['weight'] * 10 + bool(row['message']) * 2
        if available == 'restricted_or_undocumented':
            score -= 40
        rows.append({'api': name, 'owner': row['owner'], 'member': row['member'], 'kind': row['kind'],
                     'score': score, 'risk_group': group['id'], 'risk_weight': group['weight'],
                     'eval_case_ids': hits, 'eval_case_count': len(hits), 'accessibility': available,
                     'has_pinned_deprecation_message': bool(row['message']),
                     'public_code_frequency': None, 'official_tutorial_code_blocks': sample_counts.get(name)})
    rows.sort(key=lambda r: (-r['score'], r['api']))
    for n, row in enumerate(rows, 1):
        row['rank'] = n
    dep = ROOT / 'api' / 'deprecated.tsv'
    corpus_text = json.dumps(corpus, ensure_ascii=False, separators=(',', ':'))
    return {'schema': 1, 'generated_by': 'tools/rank_legacy.py', 'ranking_kind': 'editorial priority, not popularity',
            'evidence_status': 'provisional',
            'official_tutorial_sample': ({'file': 'tutorial-sample.json', 'sha256': hashlib.sha256(sample_path.read_bytes()).hexdigest(),
                                          'source': sample['source'], 'measurement': sample['measurement'],
                                          'used_in_score': False} if sample else {'status': 'not_sampled'}),
            'measured_model_outputs': {'status': 'not_sampled', 'reason': 'Eval prompt/fixture mentions are not measured generated-output failures.'},
            'public_code_frequency': {'status': 'not_sampled', 'reason': 'No representative public-code corpus was sampled; no frequency measurements are claimed.'},
            'signals': {'eval_cases': len(corpus), 'eval_corpus_sha256': hashlib.sha256(corpus_text.encode()).hexdigest(),
                        'deprecated_tsv_sha256': hashlib.sha256(dep.read_bytes()).hexdigest(),
                        'score_formula': '20 * min(exact eval-case mentions, 5) + 10 * declared risk weight + 2 * has pinned deprecation message - 40 * restricted/undocumented'},
            'rows': rows}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--check', action='store_true')
    ap.add_argument('--release-gate', action='store_true', help='fail while empirical public-code/model-output ranking evidence is absent')
    args = ap.parse_args()
    text = json.dumps(build(), indent=1, ensure_ascii=False) + '\n'
    target = DIR / 'ranking.json'
    if args.check:
        if not target.exists() or target.read_text(encoding='utf-8') != text:
            print('Legacy ranking is stale: python tools/rank_legacy.py')
            return 1
    else:
        target.write_text(text, encoding='utf-8')
    print(f"legacy ranking: {len(json.loads(text)['rows'])} rows; representative public-code frequencies absent")
    if args.release_gate:
        print('BLOCKED: editorial ranking is provisional; representative public/historical-tutorial and measured model-output evidence have not been sampled')
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
