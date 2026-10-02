#!/usr/bin/env python3
"""Fail-closed full-release gate. Infrastructure passing does not mean engine/A-B/host evidence exists."""
from __future__ import annotations
import argparse
import datetime as dt
import hashlib
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HOSTS = {'claude-code-personal', 'claude-code-project', 'claude.ai', 'codex', 'cursor'}


def package_fingerprint() -> str:
    import check_packaging
    digest = hashlib.sha256()
    for source, rel in check_packaging.files():
        digest.update(rel.as_posix().encode() + b'\0' + source.read_bytes() + b'\0')
    return digest.hexdigest()


def check_host_evidence(path: Path) -> tuple[bool, str]:
    if not path.exists():
        return False, 'Actual host installation/upload receipts are missing'
    data = json.loads(path.read_text(encoding='utf-8'))
    rows = data.get('hosts', [])
    if {row.get('host') for row in rows} != HOSTS or len(rows) != len(HOSTS):
        return False, 'Need exactly personal/project Claude Code, claude.ai, Codex, and Cursor'
    fingerprint = package_fingerprint()
    for row in rows:
        if row.get('status') != 'VERIFIED' or row.get('package_sha256') != fingerprint:
            return False, f"{row['host']}: pending or not bound to current package"
        timestamp = dt.datetime.fromisoformat(row['tested_on'].replace('Z', '+00:00'))
        if timestamp.tzinfo is None or timestamp > dt.datetime.now(dt.timezone.utc):
            return False, f"{row['host']}: invalid actual test timestamp"
        artifacts = row.get('artifacts', [])
        if not artifacts:
            return False, f"{row['host']}: no raw acceptance artifacts"
        for artifact in artifacts:
            location = (ROOT / artifact['path']).resolve()
            if not location.is_relative_to(ROOT) or not location.is_file():
                return False, f"{row['host']}: missing or external artifact"
            if hashlib.sha256(location.read_bytes()).hexdigest() != artifact.get('sha256'):
                return False, f"{row['host']}: artifact digest mismatch"
        required = {'skill_discovered', 'api_lookup_from_foreign_cwd'}
        if row['host'] == 'claude.ai':
            required = {'upload_accepted', 'skill_enabled', 'api_lookup'}
        if not required <= set(row.get('passed_checks', [])):
            return False, f"{row['host']}: incomplete host acceptance checks"
    return True, 'All actual host receipts match this package'


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ab-run', type=Path, help='completed real full-set A/B run directory')
    parser.add_argument('--host-evidence', type=Path, default=ROOT / 'maintainers' / 'host-acceptance.json')
    parser.add_argument('--skip-check-all', action='store_true', help='diagnostic only; release remains blocked')
    args = parser.parse_args()
    checks = []
    def run(label: str, command: list[str]):
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
        checks.append({'gate': label, 'status': 'PASS' if result.returncode == 0 else 'BLOCKED',
                       'command': command, 'output': (result.stdout + result.stderr)[-20000:]})
    if not args.skip_check_all:
        run('aggregate checks', [sys.executable, 'tools/check_all.py'])
        report = json.loads((ROOT / 'qa/report.json').read_text())
        if any(row['status'] != 'PASS' for row in report['results']):
            checks[-1]['status'] = 'BLOCKED'
    else:
        checks.append({'gate': 'aggregate checks', 'status': 'BLOCKED', 'output': 'NOT RUN'})
    lock = json.loads((ROOT / 'sources/lock.json').read_text())
    age = (dt.datetime.now(dt.timezone.utc).date() - dt.date.fromisoformat(lock['fetched_on'])).days
    checks.append({'gate': 'snapshot at most 14 days old', 'status': 'PASS' if 0 <= age <= 14 else 'BLOCKED', 'age_days': age})
    run('dump-derived relevant legacy coverage and curation', [sys.executable, 'tools/check_legacy.py', '--check', '--release-gate'])
    run('fact mention bindings', [sys.executable, 'tools/check_fact_mentions.py'])
    run('semantic must-to-refs coverage', [sys.executable, 'tools/check_eval_coverage.py'])
    run('balanced evaluation and clean holdout', [sys.executable, 'tools/check_eval_bank.py', '--require-ready'])
    run('exact token accounting', [sys.executable, 'tools/check_content_budget.py', '--require-tokenizer'])
    run('all ten engine smoke receipts', [sys.executable, 'tools/check_engine_evidence.py'])
    if args.ab_run:
        run('real full A/B evidence after passing pilot', [sys.executable, 'tools/run_ab.py', 'report', str(args.ab_run), '--release-gate'])
    else:
        checks.append({'gate': 'real full A/B evidence after passing pilot', 'status': 'BLOCKED', 'output': 'NOT RUN; no run directory supplied'})
    try:
        ok, reason = check_host_evidence(args.host_evidence)
    except (ValueError, KeyError, TypeError) as error:
        ok, reason = False, str(error)
    checks.append({'gate': 'actual host installs and upload', 'status': 'PASS' if ok else 'BLOCKED', 'output': reason})
    passed = all(row['status'] == 'PASS' for row in checks)
    result = {'release': '3.0', 'status': 'READY' if passed else 'BLOCKED', 'checks': checks,
              'package_sha256': package_fingerprint()}
    (ROOT / 'qa').mkdir(exist_ok=True)
    (ROOT / 'qa/release-gates.json').write_text(json.dumps(result, indent=2) + '\n')
    for row in checks:
        print(row['status'] + '  ' + row['gate'])
    print('Full release: ' + result['status'])
    return 0 if passed else 1

if __name__ == '__main__':
    raise SystemExit(main())
