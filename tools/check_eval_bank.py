#!/usr/bin/env python3
"""D6 structural audit and hash-bound, provenance-aware development/holdout split.

A custody attestation is not cryptographic proof of model non-exposure. Operators
must keep sealed cases unavailable to dataset/skill authors until final evaluation.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()


def case_hash(case, root):
    files = set(case.get('project', {}).values())
    if case.get('fixture'):
        files.add(case['fixture'])
    payload = {'case': case, 'files': {p: safe_file(root, p).read_text(encoding='utf-8') for p in sorted(files)}}
    return hashlib.sha256(canonical(payload)).hexdigest()


def safe_file(root, value):
    p = Path(value)
    if p.is_absolute() or '..' in p.parts or '\\' in value:
        raise ValueError('unsafe path: ' + value)
    target = root / p
    if target.is_symlink() or root.resolve() not in target.resolve().parents:
        raise ValueError('path escapes root: ' + value)
    return target


def load_cases(root):
    cases = []
    seen = set()
    for path in sorted((root / 'evals/cases').glob('*.jsonl')):
        for line in path.read_text(encoding='utf-8').splitlines():
            if not line.strip():
                continue
            c = json.loads(line)
            if c['id'] in seen or c['category'] != path.stem:
                raise ValueError('duplicate ID or mismatched category: ' + c['id'])
            seen.add(c['id'])
            cases.append(c)
    return cases


def audit(root=ROOT):
    root = Path(root)
    errors, clean, seal_skill_hashes = [], [], set()
    categories = defaultdict(lambda: {'count': 0, 'russian': 0, 'broken_code_fixtures': 0})
    cases = load_cases(root)
    split_path = root / 'evals/split.json'
    split = json.loads(split_path.read_text()) if split_path.exists() else {}
    entries = split.get('cases', {})
    exposure_path = root / 'evals/development-exposure.json'
    exposed = set(json.loads(exposure_path.read_text())) if exposure_path.exists() else set()
    defects_path = root / 'evals/fixture-defects.json'
    defects = json.loads(defects_path.read_text()) if defects_path.exists() else {}
    if split.get('schema_version') != 1:
        errors.append('missing/unsupported frozen split')
    if set(entries) != {c['id'] for c in cases}:
        errors.append('split IDs do not match bank')
    pilot_path = root / 'evals/pilot.json'
    pilot = set(json.loads(pilot_path.read_text())) if pilot_path.exists() else set()
    for c in cases:
        cid = c['id']
        stat = categories[c['category']]
        stat['count'] += 1
        stat['russian'] += c.get('lang') == 'ru'
        paths = list(c.get('project', {}).values()) + ([c['fixture']] if c.get('fixture') else [])
        if any(Path(p).suffix in ('.luau', '.lua', '.py') and safe_file(root, p).is_file()
               and safe_file(root, p).read_text().strip() and (defects.get(p) or c.get('fixture_defect')) for p in paths):
            stat['broken_code_fixtures'] += 1
        entry = entries.get(cid, {})
        if entry.get('sha256') != case_hash(c, root):
            errors.append(f'{cid}: frozen content hash mismatch')
            continue
        if entry.get('exposure') == 'development':
            continue
        if entry.get('exposure') != 'sealed_holdout':
            errors.append(f'{cid}: unknown exposure status')
            continue
        p = entry.get('provenance', {})
        if cid in pilot or cid in exposed or p.get('ever_development_exposed') is not False:
            errors.append(f'{cid}: contaminated holdout')
            continue
        required = ('external_author', 'sealed_at', 'skill_commit', 'skill_sha256', 'custodian', 'seal_artifact', 'seal_sha256')
        if not all(isinstance(p.get(k), str) and p[k].strip() for k in required) or p.get('no_development_use') is not True:
            errors.append(f'{cid}: missing independent custody attestation')
            continue
        artifact = safe_file(root, p['seal_artifact'])
        if not artifact.is_file() or hashlib.sha256(artifact.read_bytes()).hexdigest() != p['seal_sha256']:
            errors.append(f'{cid}: missing or modified seal artifact')
            continue
        seal = json.loads(artifact.read_text())
        if (seal.get('case_hashes', {}).get(cid) != entry['sha256'] or
                any(seal.get(k) != p[k] for k in ('external_author', 'sealed_at', 'skill_commit', 'skill_sha256', 'custodian')) or
                seal.get('no_development_use') is not True or seal.get('ever_development_exposed') is not False):
            errors.append(f'{cid}: custody artifact does not bind provenance and content')
            continue
        clean.append(cid)
        seal_skill_hashes.add(p['skill_sha256'])
    for cat, stat in sorted(categories.items()):
        if stat['count'] < 8: errors.append(f'{cat}: fewer than 8 cases')
        if not stat['russian']: errors.append(f'{cat}: missing Russian case')
        if not stat['broken_code_fixtures']: errors.append(f'{cat}: missing documented broken-code fixture')
    if not cases: errors.append('empty bank')
    fraction = len(clean) / len(cases) if cases else 0.0
    if fraction < 0.30: errors.append('clean holdout fraction below 30%')
    # Holdout must cover each category for category-level D7 comparisons.
    clean_categories = {c['category'] for c in cases if c['id'] in clean}
    if set(categories) - clean_categories: errors.append('clean holdout does not cover every category')
    readiness_only = {'clean holdout fraction below 30%', 'clean holdout does not cover every category'}
    structural_errors = [error for error in errors if error not in readiness_only]
    return {'valid': not errors, 'structural_valid': not structural_errors, 'structural_errors': structural_errors, 'total': len(cases), 'categories': dict(sorted(categories.items())),
            'clean_holdout_ids': sorted(clean), 'fraction': fraction, 'errors': errors,
            'seal_skill_sha256': sorted(seal_skill_hashes),
            'provenance_limit': 'Custody artifacts are operator attestations; independent access isolation must be audited.'}


def freeze_development(root=ROOT):
    """Refresh development hashes only; never silently demote or relabel holdout."""
    root = Path(root)
    path = root / 'evals/split.json'
    old = json.loads(path.read_text()) if path.exists() else {}
    if any(e.get('exposure') != 'development' for e in old.get('cases', {}).values()):
        raise ValueError('refusing to overwrite a split containing non-development cases')
    cases = load_cases(root)
    exposure_path = root / 'evals/development-exposure.json'
    exposed = set(json.loads(exposure_path.read_text())) if exposure_path.exists() else set()
    exposed.update(c['id'] for c in cases)
    exposure_path.write_text(json.dumps(sorted(exposed), indent=2) + '\n')
    manifest = {'schema_version': 1, 'policy': 'All author-visible cases are permanently development-exposed. Never relabel them as holdout.',
                'cases': {c['id']: {'sha256': case_hash(c, root), 'exposure': 'development',
                           'provenance': {'ever_development_exposed': True}} for c in cases}}
    path.write_text(json.dumps(manifest, ensure_ascii=False, sort_keys=True, indent=2) + '\n')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--freeze-development', action='store_true')
    p.add_argument('--require-ready', action='store_true', help='Exit 2 unless all structural and holdout gates pass')
    args = p.parse_args()
    if args.freeze_development: freeze_development()
    result = audit()
    print(json.dumps(result, ensure_ascii=False, indent=2))
    if not result['structural_valid']:
        return 1
    return 2 if args.require_ready and not result['valid'] else 0

if __name__ == '__main__':
    raise SystemExit(main())
