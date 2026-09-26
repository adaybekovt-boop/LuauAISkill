#!/usr/bin/env python3
"""Run every repository check and write qa/report.json. Exit 1 if any check fails.

Checks (in order): embedded code up to date, legacy catalog rendered, API references, source citations, links,
tool unit tests, and — when the pinned toolchain and sources are present — Luau typechecking + Luau CLI tests.
Missing toolchain/sources make the code check SKIPPED (reported, never silently passed).

  python tools/check_all.py            all checks
  python tools/check_all.py --fast     skip the Luau typecheck/tests
"""
from __future__ import annotations

import datetime as dt
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PY = sys.executable
CHECKS = [
    ("embedded code up to date", [PY, "tools/embed_code.py", "--check"]),
    ("legacy catalog rendered", [PY, "tools/render_legacy.py", "--check"]),
    ("API references", [PY, "tools/check_api_refs.py"]),
    ("source citations", [PY, "tools/check_sources.py", "--check"]),
    ("links and anchors", [PY, "tools/check_links.py"]),
    ("tool unit tests", [PY, "-m", "unittest", "discover", "-s", "tests", "-q"]),
]
CODE_CHECK = ("Luau typecheck + CLI tests", [PY, "tools/check_code.py"])


def toolchain_ready() -> bool:
    bin_dir = ROOT / ".cache" / "bin"
    defs = ROOT / ".cache" / "sources" / "luau-lsp" / "scripts" / "globalTypes.None.d.luau"
    return defs.exists() and any(bin_dir.glob("luau-lsp*")) and any(bin_dir.glob("luau*"))


def main() -> int:
    fast = "--fast" in sys.argv
    checks = list(CHECKS)
    skipped = []
    if not fast and toolchain_ready():
        checks.append(CODE_CHECK)
    else:
        skipped.append(CODE_CHECK[0] + (" (--fast)" if fast else
                       " (run tools/install_toolchain.py and tools/fetch_sources.py first)"))
    results = []
    failed = 0
    for name, cmd in checks:
        res = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
        tail = (res.stdout + res.stderr).strip().splitlines()[-3:]
        ok = res.returncode == 0
        failed += not ok
        results.append({"check": name, "status": "PASS" if ok else "FAIL", "command": " ".join(cmd[1:]),
                        "tail": tail})
        print(f"{'PASS' if ok else 'FAIL'}  {name}" + ("" if ok else "\n      " + "\n      ".join(tail)))
    for name in skipped:
        results.append({"check": name, "status": "SKIPPED"})
        print(f"SKIP  {name}")
    report = {"generated": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"), "results": results}
    (ROOT / "qa").mkdir(exist_ok=True)
    (ROOT / "qa" / "report.json").write_text(json.dumps(report, indent=1) + "\n", encoding="utf-8")
    print(f"\n{len(results) - failed - len(skipped)} passed, {failed} failed, {len(skipped)} skipped → qa/report.json")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
