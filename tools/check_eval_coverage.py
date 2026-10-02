#!/usr/bin/env python3
"""Audit every eval must against its declared refs; lexical overlap is triage only.

A supported obligation requires an explicit semantic review with an exact current
quote in a declared ref and a rationale. The checker validates evidence integrity,
not the truth of the reviewer's reasoning. Missing/ambiguous/unreviewed obligations
fail the gate. No model, network, or paid judge is invoked by this command.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
STOP = set('a an and are as at be by for from has in is it no not of on or the to use with answer'.split())


def tokens(text: str) -> set[str]:
    return {word for word in re.findall(r'[\w]+', text.casefold()) if len(word) > 2 and word not in STOP}


def local_file(root: Path, name: str) -> Path:
    path = (root / name).resolve()
    if not path.is_relative_to(root.resolve()) or not path.is_file():
        raise ValueError(f'not a repository file: {name}')
    return path


def inspect(root: Path = ROOT, reviews_path: Path | None = None) -> dict:
    errors: list[str] = []
    cases = {}
    hashes = {}
    for path in sorted((root / 'evals/cases').glob('*.jsonl')):
        hashes[path.relative_to(root).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
        for line_no, line in enumerate(path.read_text(encoding='utf-8').splitlines(), 1):
            if not line.strip():
                continue
            try:
                case = json.loads(line)
                if not isinstance(case.get('id'), str) or not case['id']:
                    raise ValueError('missing case id')
                if case['id'] in cases:
                    raise ValueError(f'duplicate case {case["id"]}')
                for field in ('must', 'refs'):
                    if not isinstance(case.get(field), list) or not case[field] or not all(isinstance(v, str) and v.strip() for v in case[field]):
                        raise ValueError(f'{case["id"]}: {field} must be a nonempty string list')
                cases[case['id']] = case
            except (ValueError, TypeError) as exc:
                errors.append(f'{path.name}:{line_no}: {exc}')
    if not cases:
        errors.append('empty case bank')
    reviews_path = reviews_path or root / 'evals/coverage/reviews.json'
    reviews = {}
    if reviews_path.exists():
        try:
            data = json.loads(reviews_path.read_text(encoding='utf-8'))
            if data.get('schema_version') != 1 or not isinstance(data.get('reviews'), list):
                raise ValueError('expected schema_version 1 and reviews list')
            for row in data['reviews']:
                key = (row.get('case_id'), row.get('must_index'))
                if not isinstance(key[0], str) or type(key[1]) is not int:
                    raise ValueError('review requires case_id and integer must_index')
                if key in reviews:
                    errors.append(f'duplicate review: {key}')
                    continue
                reviews[key] = row
        except (ValueError, TypeError, AttributeError) as exc:
            errors.append(f'invalid reviews: {exc}')
    documents = {}
    for case in cases.values():
        for ref in case['refs']:
            if ref not in documents:
                try:
                    documents[ref] = local_file(root, ref).read_text(encoding='utf-8')
                except (ValueError, UnicodeError) as exc:
                    errors.append(f'{case["id"]}: {exc}')
                    documents[ref] = ''
    obligations = []
    for case in cases.values():
        for index, must in enumerate(case['must']):
            key = (case['id'], index)
            review = reviews.pop(key, None)
            status = 'unreviewed'
            issues = []
            if review is not None:
                status = review.get('status', 'invalid')
                if status not in ('supported', 'missing', 'ambiguous'):
                    issues.append('invalid status')
                if review.get('must') != must:
                    issues.append('stale must text')
                if review.get('must_sha256') != hashlib.sha256(must.encode('utf-8')).hexdigest():
                    issues.append('missing or stale must_sha256')
                for field in ('reviewer', 'reviewed_at', 'rationale'):
                    if not isinstance(review.get(field), str) or not review[field].strip():
                        issues.append(f'missing {field}')
                evidence = review.get('evidence', [])
                if not isinstance(evidence, list):
                    issues.append('evidence must be a list')
                    evidence = []
                if status == 'supported' and not evidence:
                    issues.append('supported requires evidence')
                for item in evidence:
                    if not isinstance(item, dict):
                        issues.append('invalid evidence record')
                        continue
                    ref, quote = item.get('ref'), item.get('quote')
                    if ref not in case['refs']:
                        issues.append(f'evidence outside declared refs: {ref}')
                    elif not isinstance(quote, str) or not quote.strip() or quote not in documents.get(ref, ''):
                        issues.append(f'quote absent from current ref: {ref}')
                if issues:
                    status = 'invalid'
                    errors.extend(f'{case["id"]} must[{index}]: {issue}' for issue in issues)
            # Candidates are search aids, never evidence or automatic approval.
            wanted = tokens(must)
            candidates = []
            if status != 'supported':
                for ref in case['refs']:
                    for lineno, line in enumerate(documents.get(ref, '').splitlines(), 1):
                        overlap = wanted & tokens(line)
                        if overlap:
                            candidates.append({'ref': ref, 'line': lineno, 'matched_terms': sorted(overlap), 'text': line})
                candidates.sort(key=lambda c: (-len(c['matched_terms']), c['ref'], c['line']))
            obligations.append({'case_id': case['id'], 'must_index': index, 'must': must,
                                'status': status, 'rationale': review.get('rationale') if review else None,
                                'candidates_not_proof': candidates[:3]})
    for key in reviews:
        errors.append(f'orphan review (case or must removed): {key}')
    counts = {status: sum(o['status'] == status for o in obligations)
              for status in ('supported', 'missing', 'ambiguous', 'unreviewed', 'invalid')}
    correction_counts = {'accepted_source_correction': 0, 'pending_adjudication': 0}
    corrections_path = root / 'evals/coverage/criterion-corrections.json'
    if corrections_path.exists():
        try:
            corrections = json.loads(corrections_path.read_text(encoding='utf-8'))['corrections']
            for correction in corrections:
                status = correction['status']
                case = cases[correction['case_id']]
                expected = correction['corrected'] if status == 'accepted_source_correction' else correction['original']
                if status not in correction_counts or case['must'][correction['must_index']] != expected:
                    raise ValueError('correction status or demand does not match current case')
                correction_counts[status] += 1
                if status == 'accepted_source_correction':
                    source = local_file(root, correction['source'])
                    if hashlib.sha256(source.read_bytes()).hexdigest() != correction['source_sha256']:
                        raise ValueError('accepted correction source hash changed')
                    if correction['source_quote'] not in source.read_text(encoding='utf-8'):
                        raise ValueError('accepted correction source quote missing')
        except (KeyError, ValueError, IndexError, TypeError) as exc:
            errors.append(f'invalid criterion correction record: {exc}')
    category_recipes: dict[str, set[str]] = {}
    for case in cases.values():
        category_recipes.setdefault(case.get('category', 'uncategorized'), set()).update(
            ref for ref in case['refs'] if ref.startswith('recipes/'))
    total = len(obligations)
    return {'schema_version': 1, 'cases': len(cases), 'must_obligations': total,
            'counts': counts, 'reviewed_coverage_percent': round(100 * counts['supported'] / total, 4) if total else 0,
            'gate_passed': not errors and total > 0 and counts['supported'] == total,
            'method': 'Exact-quote integrity check of explicit semantic reviews; lexical candidates are NOT proof. Semantic judgments require reviewer scrutiny.',
            'criterion_corrections': correction_counts,
            'category_recipe_refs': {category: sorted(refs) for category, refs in sorted(category_recipes.items())},
            'categories_without_recipe_refs': sorted(category for category, refs in category_recipes.items() if not refs),
            'case_files_sha256': hashes, 'errors': errors, 'obligations': obligations}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'evals/coverage/report.json')
    parser.add_argument('--report-only', action='store_true', help='Write a diagnostic without making unresolved coverage a gate failure')
    args = parser.parse_args()
    report = inspect()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    print(f"D5: {report['counts']['supported']}/{report['must_obligations']} reviewed supported; "
          f"{report['reviewed_coverage_percent']}%; counts={report['counts']}; gate_passed={report['gate_passed']}")
    for error in report['errors']:
        print(error)
    return int(bool(report['errors']) or (not args.report_only and not report['gate_passed']))


if __name__ == '__main__':
    raise SystemExit(main())
