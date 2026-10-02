#!/usr/bin/env python3
"""Record a maintainer's actual tools/list response; never synthesize a server inventory."""
from __future__ import annotations
import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('capture', type=Path, help='actual JSON tools/list response saved by maintainer')
    p.add_argument('--server-version', required=True)
    p.add_argument('--captured-on', required=True, help='actual capture UTC timestamp, ISO 8601')
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    date = dt.datetime.fromisoformat(a.captured_on.replace('Z', '+00:00'))
    if date.tzinfo is None or date > dt.datetime.now(dt.timezone.utc):
        p.error('capture timestamp must be timezone-aware and not in the future')
    raw = a.capture.read_bytes()
    data = json.loads(raw)
    tool_list = data.get('tools', data.get('result', {}).get('tools'))
    if not isinstance(tool_list, list) or not tool_list or not all(isinstance(t, dict) and isinstance(t.get('name'), str) and isinstance(t.get('inputSchema'), dict) for t in tool_list):
        p.error('expected nonempty actual tools/list response with names and inputSchema')
    result = {'captured_on': date.isoformat(), 'server_version': a.server_version,
              'capture_sha256': hashlib.sha256(raw).hexdigest(), 'tools': tool_list,
              'evidence': 'MAINTAINER-CAPTURED tool inventory only; no execution claim'}
    a.output.parent.mkdir(parents=True, exist_ok=True)
    a.output.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(f'Recorded {len(tool_list)} tools; this does not establish engine execution.')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
