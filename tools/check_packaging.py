#!/usr/bin/env python3
"""Exercise isolated host layouts and portable ZIP; not evidence of actual host acceptance."""
from __future__ import annotations
import argparse
import json
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXCLUDE = {'.git', '.cache', '__pycache__', 'indexes', 'qa', 'runs', 'host-evidence'}
RUNTIME_DIRS = {'api', 'evals', 'examples', 'handbook', 'licenses', 'maintainers', 'recipes', 'references', 'sources', 'tests', 'tools', 'tracks'}
PORTABLE = {'name', 'description', 'license', 'compatibility', 'metadata', 'allowed-tools'}
LAYOUTS = {
    'claude-code-personal': '.claude/skills/tk-luau-roblox',
    'claude-code-project': 'project/.claude/skills/tk-luau-roblox',
    'codex': 'project/.agents/skills/tk-luau-roblox',
    'cursor': 'project/.cursor/skills/tk-luau-roblox',
}


def files(root: Path = ROOT):
    for path in sorted(root.rglob('*')):
        rel = path.relative_to(root)
        allowed = (len(rel.parts) == 1 and (path.suffix == '.md' or path.name == 'VERSION')) or rel.parts[0] in RUNTIME_DIRS
        if rel.as_posix() == 'maintainers/host-acceptance.json':
            continue
        if allowed and path.is_file() and not path.is_symlink() and not (set(rel.parts) & EXCLUDE) and path.suffix not in {'.pyc', '.zip'} and not any(p.startswith('.') for p in rel.parts):
            yield path, rel


def portable_frontmatter(text: str) -> None:
    if not text.startswith('---\n'):
        raise ValueError('SKILL.md requires YAML frontmatter')
    header = text.split('---', 2)[1]
    fields = {line.split(':', 1)[0] for line in header.splitlines()
              if line and not line[0].isspace() and ':' in line}
    if not {'name', 'description'} <= fields or fields - PORTABLE:
        raise ValueError(f'nonportable frontmatter fields: {sorted(fields - PORTABLE)}')


def build_zip(target: Path) -> None:
    portable_frontmatter((ROOT / 'SKILL.md').read_text(encoding='utf-8'))
    target.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(target, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        for source, rel in files():
            info = zipfile.ZipInfo('tk-luau-roblox/' + rel.as_posix(), date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            archive.writestr(info, source.read_bytes())


def run_checks() -> dict:
    results = []
    with tempfile.TemporaryDirectory(prefix='luau-packaging-') as temp:
        base = Path(temp)
        foreign = base / 'unrelated-project'
        foreign.mkdir()
        (foreign / 'legacy.luau').write_text('local x = wait(1)\n', encoding='utf-8')
        for host, layout in LAYOUTS.items():
            install = base / host / layout
            for source, rel in files():
                destination = install / rel
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, destination)
            portable_frontmatter((install / 'SKILL.md').read_text(encoding='utf-8'))
            for args in [('api.py', 'Part.Anchored'), ('search.py', 'session locking'),
                         ('scan_legacy.py', str(foreign / 'legacy.luau'))]:
                cmd = [sys.executable, '-I', str(install / 'tools' / args[0]), *args[1:]]
                result = subprocess.run(cmd, cwd=foreign, capture_output=True, text=True,
                                        env={'PATH': str(Path(sys.executable).parent)}, timeout=90)
                # scanner signals detections through its documented nonzero result.
                valid = result.returncode == 0 or (args[0] == 'scan_legacy.py' and result.returncode == 1)
                if not valid or not result.stdout.strip():
                    raise RuntimeError(f'{host} {args[0]} failed: {result.stdout} {result.stderr}')
                results.append({'host': host, 'tool': args[0], 'status': 'PASS', 'cwd': 'foreign'})
        archive_path = base / 'skill.zip'
        build_zip(archive_path)
        with zipfile.ZipFile(archive_path) as archive:
            assert archive.testzip() is None
            assert 'tk-luau-roblox/SKILL.md' in archive.namelist()
            assert not any(set(Path(n).parts) & EXCLUDE for n in archive.namelist())
            portable_frontmatter(archive.read('tk-luau-roblox/SKILL.md').decode())
        results.append({'host': 'claude.ai', 'status': 'PACKAGE_VALIDATED',
                        'actual_upload': 'NOT RUN'})
    return {'scope': 'isolated filesystem layouts and foreign-CWD execution; not actual host installs',
            'actual_host_acceptance': 'NOT RUN', 'results': results}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--zip', type=Path)
    parser.add_argument('--report', type=Path, default=ROOT / 'qa' / 'packaging.json')
    args = parser.parse_args()
    report = run_checks()
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    if args.zip:
        build_zip(args.zip.resolve())
    print(f"PASS {len(report['results'])} packaging checks; actual host acceptance NOT RUN")
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
