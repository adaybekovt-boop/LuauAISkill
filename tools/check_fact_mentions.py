#!/usr/bin/env python3
"""Audit fact-ID bindings in freshness prose, limits.md, and handbook limit tables.

This is a lexical coverage gate, NOT a semantic entailment judge. Numeric/status
mentions in other chapter tables are included as review candidates, never quietly
counted as covered. Code fences, link destinations, API identifier digits and table
separators are not prose claims. Inline code remains visible (budgets use it).
"""
from __future__ import annotations

import argparse
from decimal import Decimal, InvalidOperation
import hashlib
import json
import re
from pathlib import Path

from render_facts import VALUE_BLOCK, cell, render, render_embedded

ROOT = Path(__file__).resolve().parents[1]
NUMBER = re.compile(r"(?<![\w])[-−+]?\d+(?:[,._]\d+)*(?:\^\d+)?(?:[kKmM]|²)?(?![\w])")
STATUS = re.compile(r"\b(?:beta|GA|general availability|fully released|full release|stable|deprecated|superseded|removed|disabled)\b", re.I)
BINDING = re.compile(r"<!--\s*fact-refs:\s*([a-z0-9,\s-]+)\s*-->")
LIMIT_CUE = re.compile(r"\b(?:limits?|maximum|minimum|quota|budget|cap|throughput)\b|[≤≥]\s*\d", re.I)


def prose(text: str) -> str:
    text = re.sub(r"<!--.*?-->", "", text)
    text = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", text)
    text = re.sub(r"(?:https?://|cd:|api:)\S+", "", text)
    # Names (Vector3, C0/C1, Action2/3), not numeric literals in inline code.
    text = re.sub(r"\b[A-Za-z_][A-Za-z_0-9]*(?:/[A-Za-z_0-9]+)*\b", lambda m: "" if any(c.isdigit() for c in m[0]) else m[0], text)
    return text


def mentions(text: str) -> list[str]:
    clean = prose(text)
    return [m[0] for m in NUMBER.finditer(clean)] + [m[0] for m in STATUS.finditer(clean)]


def blocks(text: str):
    """Yield line-numbered headings, paragraphs and individual table rows."""
    lines = text.splitlines()
    fenced = False
    paragraph: list[str] = []
    start = 0
    for index, line in enumerate(lines, 1):
        if line.lstrip().startswith(('```', '~~~')):
            if paragraph:
                yield start, '\n'.join(paragraph)
                paragraph = []
            fenced = not fenced
            continue
        if fenced:
            continue
        separate = not line.strip() or line.startswith(('#', '|', '- '))
        if separate and paragraph:
            yield start, '\n'.join(paragraph)
            paragraph = []
        if line.startswith(('#', '|')):
            yield index, line
        elif line.strip():
            if not paragraph:
                start = index
            paragraph.append(line)
    if paragraph:
        yield start, '\n'.join(paragraph)


def number_key(token: str) -> str:
    token = token.replace("−", "-").replace(",", "").replace("_", "").rstrip("²")
    factor = 1
    if token[-1:] in ("k", "K", "m", "M"):
        factor = 1000 if token[-1:].lower() == "k" else 1000000
        token = token[:-1]
    if "^" in token:
        base, power = token.split("^")
        if int(power) > 64:
            return token
        token = str(int(base) ** int(power))
    try:
        return str((Decimal(token) * factor).normalize())
    except InvalidOperation:
        return token


def numeric_claims(text: str) -> set[str]:
    return {number_key(m[0]) for m in NUMBER.finditer(prose(text))}


STATUS_ALIASES = {"ga": "ga", "general availability": "ga", "fully released": "ga",
                  "full release": "ga", "stable": "ga"}
NEGATION = re.compile(r"(?:\bnot\b|\bnever\b|\bno longer\b|\bisn't\b|\baren't\b|\bdoesn't\b|\bwithout\b)(?:\s+\w+){0,5}\s*$", re.I)


def status_claims(text: str) -> set[tuple[str, bool]]:
    """Canonical lexical status and polarity; subject/scope still needs review.

    Do not equate 'not beta' with GA: a removed feature can also be not beta.
    Only short explicit negations are recognized; this is not a prose entailment
    parser, and compound/ambiguous claims must be reviewed by a maintainer.
    """
    clean = prose(text).replace("`", "").replace("*", "")
    result = set()
    for match in STATUS.finditer(clean):
        prefix = re.split(r"[.;|\n,]", clean[:match.start()])[-1]
        negative = bool(NEGATION.search(prefix))
        result.add((STATUS_ALIASES.get(match[0].lower(), match[0].lower()), negative))
    return result


def supported_statuses(fact: dict) -> set[tuple[str, bool]]:
    # GA/beta/deprecated positive rollout claims require the structured status,
    # not an incidental historical mention in evidence or explanatory notes.
    result = set()
    registered = fact.get("status")
    if registered in {"ga", "beta", "deprecated"}:
        result.add((registered, False))
    for field in ("statement", "value", "evidence"):
        value = fact.get(field, "")
        parts = value if isinstance(value, list) else [value]
        for part in parts:
            if not isinstance(part, str):
                continue
            for status, negative in status_claims(part):
                if negative or status not in {"ga", "beta", "deprecated"}:
                    result.add((status, negative))
    return result


def audit(root: Path, data: dict) -> dict:
    indexed = {f['id']: f for f in data['facts']}
    ids = set(indexed)
    try:
        generated_limits_rows = set(render(data).splitlines())
    except KeyError:
        generated_limits_rows = set()
    review_path = root / 'maintainers/fact-mention-review.json'
    decisions = json.loads(review_path.read_text(encoding='utf-8')) if review_path.exists() else {'rows': []}
    reviewed = {(r['path'], r['row_sha256']): r for r in decisions['rows']}
    allowed_classifications = {'design_example', 'code_example', 'other_product_version', 'navigation_identifier', 'language_syntax', 'runtime_state'}
    adjudicated = []
    rows, review, errors, files, exclusions = [], [], [], {}, []
    paths = [root / 'SKILL.md', root / 'references/limits.md', *sorted((root / 'handbook').rglob('*.md'))]
    for path in paths:
        relative = path.relative_to(root).as_posix()
        if not path.exists():
            errors.append(f'{relative}: required file missing')
            continue
        raw = path.read_text(encoding='utf-8')
        files[relative] = hashlib.sha256(raw.encode()).hexdigest()
        freshness, heading, table_limit = False, '', False
        for line, text in blocks(raw):
            if text.startswith('#'):
                heading = text
                if relative == 'SKILL.md' and text.startswith('## '):
                    freshness = text.lower().startswith('## freshness')
                table_limit = bool(LIMIT_CUE.search(text))
                # Snapshot version/date heading is reported, not silently ignored.
                if not freshness:
                    continue
            if text.startswith('|'):
                if re.fullmatch(r'[|:\s-]+', text):
                    continue
                if re.search(r'\|\s*(?:Limit|Maximum|Quota|Budget)\s*\|', text, re.I):
                    table_limit = True
            elif relative.startswith('handbook/'):
                continue
            if relative == 'SKILL.md' and not freshness:
                continue
            values = mentions(text)
            if not values:
                continue
            scoped = freshness if relative == 'SKILL.md' else (relative == 'references/limits.md' or table_limit or bool(LIMIT_CUE.search(prose(text))))
            decision = reviewed.get((relative, hashlib.sha256(text.encode()).hexdigest()))
            example = re.search(r'<!-- fact-example: (.+?) -->', text)
            if example:
                if not decision or decision.get('classification') not in allowed_classifications or not decision.get('reason'):
                    errors.append(f'{relative}:{line}: non-fact exemption lacks content-addressed scope review')
                else:
                    exclusions.append({'path': relative, 'line': line, 'reason': example[1], 'text': text})
                    continue
            if relative == 'references/limits.md' and not text.startswith('|'):
                # Generated glossary defines statuses and provenance, not platform facts.
                if text.startswith(('Dated statements', 'Status:')):
                    exclusions.append({'path': relative, 'line': line, 'reason': 'Generated glossary/provenance explanation, not a platform status claim', 'text': text})
                    continue
            refs = re.findall(r'<!-- fact-value: ([a-z0-9-]+)(?:\[[0-9]+\])? -->', text)
            for match in BINDING.finditer(text):
                refs.extend(x.strip() for x in match[1].split(',') if x.strip())
            if text.startswith('|'):
                refs += re.findall(r'`([a-z][a-z0-9-]+)`:', text)
            entry = {'path': relative, 'line': line, 'mentions': values, 'fact_ids': sorted(set(refs)), 'text': text}
            scoped = scoped or bool(refs)
            if not scoped:
                decision = reviewed.get((relative, hashlib.sha256(text.encode()).hexdigest()))
                if decision and decision.get('classification') in allowed_classifications and decision.get('reason'):
                    adjudicated.append({**entry, 'classification': decision['classification'], 'reason': decision['reason']})
                else:
                    review.append(entry)
                    errors.append(f'{relative}:{line}: unreviewed numeric/status table row; bind facts or explicitly adjudicate its scope')
                continue
            unknown = sorted(set(refs) - ids)
            unsupported = set()
            unsupported_statuses = set()
            render_valid = True
            if relative == 'references/limits.md' and text not in generated_limits_rows:
                render_valid = False
                errors.append(f'{relative}:{line}: generated limits row differs from registry rendering')
            examples = re.search(r'<!-- fact-examples: (.+?) -->', text)
            example_numbers = set()
            if examples:
                spec = json.loads(examples[1])
                if not decision or decision.get('classification') != 'mixed_examples' or decision.get('values') != spec.get('values') or not decision.get('reason'):
                    errors.append(f'{relative}:{line}: mixed-row examples lack matching content-addressed review')
                else:
                    example_numbers = {number_key(str(v)) for v in spec['values']}
                    exclusions.append({'path': relative, 'line': line, 'reason': spec['reason'], 'numeric_examples': spec['values']})
            if refs and not unknown and relative != 'references/limits.md':
                allowed = set()
                allowed_statuses = set()
                for fid in refs:
                    fact = indexed[fid]
                    allowed |= numeric_claims(json.dumps(fact.get('value'), ensure_ascii=False))
                    allowed_statuses |= supported_statuses(fact)
                # Numeric support is only the registered value; an incidental
                # number in a quotation, note, source URL or date cannot bless it.
                unsupported = numeric_claims(text) - allowed - example_numbers
                for block in VALUE_BLOCK.finditer(text):
                    if render_embedded(block[0], data) != block[0]:
                        errors.append(f'{relative}:{line}: fact-value block differs from its registered value')
                        unsupported |= numeric_claims(block[0])
                generated_row = False
                for fid in set(refs):
                    f = indexed[fid]
                    canonical = '| ' + ' | '.join(cell(v) for v in
                        (f"`{fid}`: {f['statement']}", f['value'], f['unit'], f['status'])) + ' |'
                    generated_row |= text == canonical
                # Non-generated literal claims require rendering, not merely an
                # ID with coincidentally equal numbers for another subject.
                if not generated_row:
                    literal_numbers = numeric_claims(VALUE_BLOCK.sub('', text)) - example_numbers
                    if literal_numbers:
                        errors.append(f'{relative}:{line}: numeric claims must use exact rendered fact-value blocks or a generated fact row')
                        unsupported |= literal_numbers
                if unsupported:
                    errors.append(f'{relative}:{line}: numbers absent from referenced facts: {", ".join(sorted(unsupported))}')
                unsupported_statuses = status_claims(text) - allowed_statuses
                if unsupported_statuses:
                    labels = [('not ' if neg else '') + status for status, neg in sorted(unsupported_statuses)]
                    errors.append(f'{relative}:{line}: statuses unsupported by referenced facts: {", ".join(labels)}')
            entry['unsupported_statuses'] = [('not ' if neg else '') + status for status, neg in sorted(unsupported_statuses)]
            entry['unsupported_numbers'] = sorted(unsupported)
            entry['covered'] = bool(refs) and not unknown and not unsupported and not unsupported_statuses and render_valid
            if unknown:
                errors.append(f'{relative}:{line}: unknown fact IDs: {", ".join(unknown)}')
            if not refs:
                errors.append(f'{relative}:{line}: unbound numeric/status mention: {", ".join(values)}')
            rows.append(entry)
    covered = sum(row['covered'] for row in rows)
    return {'schema_version': 1, 'scope': 'SKILL freshness including its heading; all limits.md numeric/status prose; handbook tables under limit headings/headers or rows with explicit limit cues',
            'boundary': 'Lexical fact-ID/numeric/status-polarity support binding, not semantic entailment. A matching number or status does not establish that its subject, scope, or qualifiers match the cited fact. Every other numeric/status chapter table row needs content-addressed scope adjudication. Code fences, link destinations, API identifier digits are excluded. No claim of repository-wide fact coverage.',
            'files_sha256': files, 'candidate_blocks': len(rows), 'covered_blocks': covered,
            'unbound_blocks': len(rows) - covered, 'coverage_percent': round(100 * covered / len(rows), 2) if rows else None,
            'explicit_non_fact_exclusions': exclusions, 'adjudicated_non_limit_rows': adjudicated, 'outside_scope_review_candidates': len(review), 'rows': rows, 'review_candidates': review, 'errors': errors}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--output', type=Path, help='Write a reproducible machine-readable audit artifact')
    args = parser.parse_args()
    try:
        data = json.loads((args.root / 'references/facts.json').read_text(encoding='utf-8'))
        result = audit(args.root, data)
    except (OSError, ValueError, KeyError, TypeError, IndexError) as error:
        print(f'ERROR {error}')
        return 1
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    print(f"fact mentions: {result['covered_blocks']}/{result['candidate_blocks']} scoped blocks bound; {result['unbound_blocks']} gaps; {result['outside_scope_review_candidates']} other table rows require review")
    for error in result['errors']:
        print('ERROR', error)
    return int(bool(result['errors']))


if __name__ == '__main__':
    raise SystemExit(main())
