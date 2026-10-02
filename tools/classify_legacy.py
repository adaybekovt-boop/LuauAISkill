#!/usr/bin/env python3
"""Generate dump-derived, fixture-executed D3 coverage; never infer migration safety from names."""
from __future__ import annotations
import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import api
import rank_legacy

ROOT = Path(__file__).resolve().parents[1]
DIR = ROOT / 'references/legacy-modernization'
MEMBER_KINDS = {'Function', 'Property', 'Event', 'Callback'}


def relevant(row):
    if row['kind'] not in MEMBER_KINDS:
        return False, 'outside member denominator; detected and reported separately'
    if 'undocumented' in api.classes().get(row['owner'], {}).get('tags', ''):
        return False, 'undocumented owner'
    if rank_legacy.accessibility(row) != 'documented':
        return False, 'restricted, not scriptable, plugin-only or undocumented member'
    return True, 'game-script candidate: neither owner nor member is flagged undocumented; actual doc presence is checked during source review'


def fixture(row, receiver='receiver'):
    name = rank_legacy.identifier(row)
    if row['kind'] == 'class':
        return f'local old = Instance.new("{name}")'
    if row['kind'] == 'EnumItem':
        return f'local old = {name}'
    if row['kind'] in ('global', 'library'):
        return f'local old = {name}(value)'
    if row['kind'] == 'datatype':
        return f'params.{name.rsplit(".", 1)[-1]}(value)'
    if not row['member'].isidentifier():
        return f'local old = {receiver}[{json.dumps(row["member"])}]'
    if row['kind'] == 'Function':
        return f'{receiver}:{row["member"]}(value)'
    return f'local old = {receiver}.{row["member"]}'


def generic_rule(row):
    name = rank_legacy.identifier(row)
    if row['kind'] == 'class':
        pattern = r'\bInstance\s*\.\s*new\s*\(\s*[\"\x27]' + re.escape(name) + r'[\"\x27]'
    elif row['kind'] in ('global', 'library', 'EnumItem'):
        pattern = r'(?<![\w.:])' + re.escape(name) + r'\b'
    else:
        member = re.escape(name.rsplit('.', 1)[-1])
        pattern = r'(?:[.:]\s*' + member + r'\b|\[\s*[\"\x27]' + member + r'[\"\x27]\s*\])'
    hint = row['message'] or ('Pinned preferred member: ' + row['preferred'] if row['preferred'] else 'No replacement established by the pinned deprecation row.')
    return 'api-deprecated:' + name, re.compile(pattern), f'{name}: {hint} Verify receiver class and migration semantics; lexical review candidate only.'


def classification(row, covered):
    name = rank_legacy.identifier(row)
    if name in covered:
        return 'curated', 'Explicit covers mapping with an executed detector fixture.'
    found = api.resolve_member(row['owner'], row['member'])
    preferred = row['preferred']
    # A stated alias, a same-owner current target and an unchanged complete signature are all required.
    candidates = re.findall(r'`(?:Class\.)?([A-Za-z0-9_]+)[.:]([A-Za-z0-9_]+)(?:\(\))?`', row['message'])
    if not preferred:
        preferred = next((m for owner, m in candidates if owner == row['owner']), '')
    target = api.resolve_member(row['owner'], preferred) if preferred else None
    explicit_alias = ('variant of' in row['message'] or 'directly renamed' in row['message'] or name in {'SocialService.PromptLinkSharing', 'TorsionSpringConstraint.LimitEnabled'})
    if found and target and explicit_alias:
        old, new = found[1], target[1]
        if old['kind'] == new['kind'] and old['type_or_signature'] == new['type_or_signature'] and 'deprecated' not in new['flags']:
            return 'one_to_one', f'Pinned alias or individually reviewed rename; same-owner {preferred} has equal kind/signature and is current.'
    if preferred or candidates or any(x in row['message'] for x in ('instead', 'replaced', 'removed', 'no longer', 'decommissioned', 'never be called')):
        return 'needs_curation', 'Nontrivial, retired, ambiguous or unproven rename: human migration guidance required.'
    return 'unresolved', 'Pinned row does not establish a safe replacement; do not guess.'


def build():
    import scan_legacy
    data = json.loads((DIR / 'catalog.json').read_text())
    covered = {a: e['id'] for e in data['entries'] for a in e.get('covers', [])}
    rules = scan_legacy.load_rules(True)
    curated = [(e['id'], re.compile(e['detect'])) for e in data['entries']]
    result = []
    for row in api.rows('deprecated.tsv'):
        name = rank_legacy.identifier(row)
        rel, reason = relevant(row)
        sample = fixture(row)
        hits = [rid for rid, rx, *_ in rules if rx.search(sample)]
        state, evidence = classification(row, covered)
        curated_id = covered.get(name)
        mapped = next((rx for rid, rx in curated if rid == curated_id), None)
        # An owner-sensitive curated detector is checked with the explicit owner too.
        owner_fixture = fixture(row, row['owner'])
        if row['kind'] in ('Property', 'Callback'):
            owner_fixture = f'{row["owner"]}.{row["member"]} = value'
        elif row['kind'] == 'Event':
            owner_fixture = f'{row["owner"]}.{row["member"]}:Connect(callback)'
        curated_detected = bool(mapped and (mapped.search(sample) or mapped.search(owner_fixture)))
        result.append({'api': name, 'kind': row['kind'], 'relevant': rel, 'scope_reason': reason,
                       'classification': state, 'classification_reason': evidence,
                       'source': {'kind': 'api', 'ref': name}, 'quote': row['message'], 'preferred': row['preferred'],
                       'fixture': sample, 'detector_hits': hits, 'detected': bool(hits),
                       'curated_entry': curated_id, 'curated_fixture': owner_fixture if curated_id else None, 'curated_detector_verified': curated_detected})
    gaps_path = DIR / 'source-gaps.json'
    reviews = {r['api']: r for r in json.loads(gaps_path.read_text())['rows']} if gaps_path.exists() else {}
    for r in result:
        if r['classification'] == 'unresolved':
            r['review_status'] = reviews.get(r['api'], {}).get('status', 'unreviewed')
    relevant_rows = [r for r in result if r['relevant']]
    counts = {state: sum(r['classification'] == state for r in relevant_rows) for state in ('curated', 'one_to_one', 'needs_curation', 'unresolved')}
    return {'schema': 1, 'generated_by': 'tools/classify_legacy.py',
            'evidence': 'Python-executed lexical scanner fixtures; no inferred receiver types, model runs or engine execution.',
            'input_sha256': hashlib.sha256((ROOT / 'api/deprecated.tsv').read_bytes()).hexdigest(),
            'denominator': 'Conservative candidate set: Function/Property/Event/Callback rows in deprecated.tsv; neither owner nor member flagged undocumented; read security None; no plugin-only or NotScriptable. Absence of an undocumented flag is not proof of member documentation. AnimationConstraint C0/C1/Part0/Part1 are direct dump members absent from owner YAML, retained rather than silently excluded; curation requires separately reviewed staff guidance.',
            'supplied_baseline_relevant': 431, 'baseline_reconciliation': '431 is a supplied estimate, not reproducible from pinned inputs; every row and exclusion reason is retained below. Do not compare denominator changes as coverage improvements.',
            'measured_baseline': {'relevant_rows': 407, 'detected_relevant_rows': 376, 'catalog_entries': 152, 'explicit_curated_relevant_rows': 274, 'method': 'Pre-change curated regexes plus old unambiguous-name fallback, executed on the same receiver fixtures.'},
            'total_deprecated_rows': len(result), 'relevant_rows': len(relevant_rows),
            'detected_relevant_rows': sum(r['detected'] for r in relevant_rows),
            'detected_all_rows': sum(r['detected'] for r in result), 'classification_counts': counts,
            'source_gap_rows': sum(r.get('review_status') == 'reviewed_source_gap' for r in relevant_rows),
            'unreviewed_rows': sum(r.get('review_status') == 'unreviewed' for r in relevant_rows),
            'remaining_curation': [r['api'] for r in relevant_rows if r['classification'] in ('needs_curation', 'unresolved')],
            'ab_output_curation': {'status': 'not_measured', 'reason': 'No real model-output artifact supplied.'},
            'rows': result}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--check', action='store_true')
    ap.add_argument('--release-gate', action='store_true')
    args = ap.parse_args()
    report = build()
    text = json.dumps(report, indent=1, ensure_ascii=False) + '\n'
    path = DIR / 'classification.json'
    stale = args.check and (not path.exists() or path.read_text() != text)
    if not args.check:
        path.write_text(text)
    print(f"D3: {report['detected_relevant_rows']}/{report['relevant_rows']} relevant detected; {report['classification_counts']}; A/B NOT MEASURED")
    if stale:
        print('ERROR classification.json stale: run python tools/classify_legacy.py')
    blocked = args.release_gate and (report['remaining_curation'] or report['ab_output_curation']['status'] != 'verified')
    if blocked:
        print('BLOCKED: D3 requires unresolved migrations and actual A/B output curation evidence.')
    return int(bool(stale or blocked or report['detected_relevant_rows'] != report['relevant_rows']))


if __name__ == '__main__':
    raise SystemExit(main())
