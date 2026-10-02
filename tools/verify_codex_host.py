#!/usr/bin/env python3
"""Verify real Codex skill discovery, without login, threads, or model inference.

Runs the installed Codex app-server against a fresh temporary HOME/CODEX_HOME
and a packaged skill copy in a temporary project's .agents/skills directory.
The receipt covers host discovery and direct foreign-CWD tool execution only;
it does not claim agent tool use, task completion, or model A/B evidence.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import queue
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path
from typing import Any

import check_packaging

ROOT = Path(__file__).resolve().parents[1]
SKILL_NAME = 'tk-luau-roblox'


def fingerprint(entries: list[tuple[Path, Path]]) -> str:
    digest = hashlib.sha256()
    for source, rel in entries:
        digest.update(rel.as_posix().encode() + b'\0' + source.read_bytes() + b'\0')
    return digest.hexdigest()


def sanitized(value: Any, base: Path) -> Any:
    """Retain protocol data while removing ephemeral paths and host identifiers."""
    if isinstance(value, str):
        return value.replace(str(base), '<TEMP>')
    if isinstance(value, list):
        return [sanitized(item, base) for item in value]
    if isinstance(value, dict):
        return {key: '<REDACTED_HOST_IDENTIFIER>' if key in {'serverName', 'installationId'}
                and item is not None else sanitized(item, base) for key, item in value.items()}
    return value


def discover(codex: str, project: Path, env: dict[str, str], timeout: float) -> dict:
    command = [codex, 'app-server', '--listen', 'stdio://',
               '-c', 'analytics.enabled=false']
    process = subprocess.Popen(command, cwd=project, env=env, stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               text=True, encoding='utf-8')
    stdout_queue: queue.Queue[str | None] = queue.Queue()
    stderr_lines: list[str] = []
    transcript: list[dict] = []

    def read_stdout() -> None:
        assert process.stdout is not None
        for line in process.stdout:
            stdout_queue.put(line)
        stdout_queue.put(None)

    def read_stderr() -> None:
        assert process.stderr is not None
        stderr_lines.extend(process.stderr)

    stdout_reader = threading.Thread(target=read_stdout, daemon=True)
    stderr_reader = threading.Thread(target=read_stderr, daemon=True)
    stdout_reader.start()
    stderr_reader.start()

    def send(message: dict) -> None:
        transcript.append({'direction': 'request', 'message': message})
        assert process.stdin is not None
        process.stdin.write(json.dumps(message) + '\n')
        process.stdin.flush()

    def receive(request_id: int) -> dict:
        deadline = time.monotonic() + timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError(f'Codex request {request_id} timed out')
            try:
                line = stdout_queue.get(timeout=remaining)
            except queue.Empty as error:
                raise TimeoutError(f'Codex request {request_id} timed out') from error
            if line is None:
                raise RuntimeError(f'Codex exited before request {request_id} completed')
            message = json.loads(line)
            transcript.append({'direction': 'response', 'message': message})
            if message.get('id') == request_id:
                if 'error' in message:
                    raise RuntimeError(f'Codex request {request_id}: {message["error"]}')
                return message['result']

    failure = None
    skills = None
    shutdown = 'stdin closed after read-only protocol checks'
    try:
        send({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {
            'clientInfo': {'name': 'luau-skill-host-verification', 'version': '1.0.0'},
            'capabilities': {'explicitGatewayOauth': True}}})
        receive(1)
        send({'jsonrpc': '2.0', 'method': 'initialized'})
        send({'jsonrpc': '2.0', 'id': 2, 'method': 'skills/list', 'params': {
            'cwds': [str(project)], 'forceReload': True}})
        skills = receive(2)
    except (OSError, ValueError, KeyError, RuntimeError, TimeoutError) as error:
        failure = str(error)
    finally:
        if process.stdin is not None:
            process.stdin.close()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            shutdown = 'SIGTERM after read-only protocol checks and stdin EOF timeout'
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                shutdown = 'SIGKILL after read-only protocol checks and shutdown timeout'
                process.kill()
                process.wait(timeout=5)
        stdout_reader.join(timeout=5)
        stderr_reader.join(timeout=5)
        for stream in (process.stdin, process.stdout, process.stderr):
            if stream is not None:
                stream.close()
    return {'command': command, 'transcript': transcript, 'skills_result': skills,
            'stderr': ''.join(stderr_lines), 'error': failure,
            'shutdown': shutdown,
            'process_returncode': process.returncode}


def discovery_passed(discovery: dict, project: Path, install: Path) -> bool:
    rows = (discovery['skills_result'] or {}).get('data', [])
    project_rows = [row for row in rows if row.get('cwd') == str(project)]
    matches = [skill for row in project_rows for skill in row.get('skills', [])
               if skill.get('name') == SKILL_NAME and
               skill.get('path') == str(install / 'SKILL.md')]
    return (discovery['error'] is None and len(project_rows) == 1 and
            not project_rows[0].get('errors') and len(matches) == 1 and
            matches[0].get('enabled') is True and matches[0].get('scope') == 'repo')


def verify(codex: str, timeout: float) -> dict:
    with tempfile.TemporaryDirectory(prefix='luau-codex-host-') as temporary:
        base = Path(temporary)
        home = base / 'home'
        codex_home = home / '.codex'
        project = base / 'project'
        foreign = base / 'unrelated-project'
        install = project / '.agents' / 'skills' / SKILL_NAME
        for directory in (home, codex_home, project, foreign, base / 'tmp'):
            directory.mkdir(parents=True, exist_ok=True)
        # A repo marker bounds project-root discovery to this disposable project.
        (project / '.git').mkdir()
        entries = list(check_packaging.files())
        before = fingerprint(entries)
        installed_entries = []
        for source, relative in entries:
            destination = install / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, destination)
            installed_entries.append((destination, relative))
        installed = fingerprint(installed_entries)
        after_copy = fingerprint(list(check_packaging.files()))
        if before != installed or before != after_copy:
            raise RuntimeError('Package changed while copying; rerun after edits settle')
        check_packaging.portable_frontmatter((install / 'SKILL.md').read_text(encoding='utf-8'))
        # Intentionally do not inherit any credentials, environment configuration,
        # user home, proxy, plugin, or session variables from the invoking process.
        env = {'HOME': str(home), 'CODEX_HOME': str(codex_home),
               'XDG_CONFIG_HOME': str(home / '.config'),
               'XDG_CACHE_HOME': str(home / '.cache'),
               'XDG_DATA_HOME': str(home / '.local' / 'share'),
               'TMPDIR': str(base / 'tmp'), 'LANG': 'C.UTF-8',
               'PATH': os.pathsep.join((str(Path(codex).parent),
                                        str(Path(sys.executable).parent), '/usr/bin', '/bin'))}
        version = subprocess.run([codex, '--version'], cwd=project, env=env,
                                 capture_output=True, text=True, timeout=timeout, check=True)
        discovery = discover(codex, project, env, timeout)
        discovered = discovery_passed(discovery, project, install)
        api_command = [sys.executable, '-I', str(install / 'tools' / 'api.py'), 'Part.Anchored']
        api = subprocess.run(api_command, cwd=foreign, env=env, capture_output=True,
                             text=True, timeout=timeout)
        api_passed = (api.returncode == 0 and 'Part.Anchored' in api.stdout and
                      'game scripts: read yes, write yes' in api.stdout)
        after = fingerprint(list(check_packaging.files()))
        stable = before == after
        checks = {'skill_discovered': discovered,
                  'api_lookup_from_foreign_cwd': api_passed,
                  'package_unchanged_during_verification': stable}
        return sanitized({
            'schema_version': 1, 'host': 'codex',
            'status': 'VERIFIED' if all(checks.values()) else 'FAILED',
            'tested_on': dt.datetime.now(dt.timezone.utc).isoformat().replace('+00:00', 'Z'),
            'package_sha256': installed, 'packaged_file_count': len(entries),
            'host_version': version.stdout.strip(), 'host_version_stderr': version.stderr,
            'scope': 'Actual Codex app-server discovery plus direct installed-tool execution',
            'model_inference': 'NOT RUN', 'agent_tool_use': 'NOT RUN',
            'login': 'NOT REQUESTED',
            'isolation': {'fresh_home': str(home), 'fresh_codex_home': str(codex_home),
                          'inherited_environment': False,
                          'rpc_methods': ['initialize', 'initialized', 'skills/list']},
            'checks': checks,
            'passed_checks': [name for name, passed in checks.items() if passed],
            'host_discovery': discovery,
            'api_lookup': {'command': api_command, 'cwd': str(foreign),
                           'returncode': api.returncode, 'stdout': api.stdout, 'stderr': api.stderr},
            'path_sanitization': ('Disposable temporary root replaced with <TEMP>; '
                                  'serverName and installationId redacted.')
        }, base)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--codex', default=shutil.which('codex'),
                        help='installed Codex executable (default: PATH lookup)')
    parser.add_argument('--report', type=Path,
                        default=ROOT / 'maintainers' / 'host-evidence' / 'codex.json')
    parser.add_argument('--timeout-seconds', type=float, default=30)
    args = parser.parse_args()
    if not args.codex:
        parser.error('Codex is not installed/on PATH; supply --codex')
    if args.timeout_seconds <= 0:
        parser.error('--timeout-seconds must be positive')
    codex = str(Path(shutil.which(args.codex) or args.codex).resolve())
    report = verify(codex, args.timeout_seconds)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(f"{report['status']} {report['host_version']}: host receipt verification")
    for name, passed in report['checks'].items():
        print(f"{'PASS' if passed else 'FAIL'} {name}")
    print('Model inference and agent tool use: NOT RUN')
    print(f"Package SHA-256: {report['package_sha256']}")
    print(f'Receipt: {args.report}')
    return 0 if report['status'] == 'VERIFIED' else 1


if __name__ == '__main__':
    raise SystemExit(main())
