#!/usr/bin/env python3
"""Read-only scan of a Roblox/Luau project for legacy/deprecated/unsafe patterns.

Uses the curated regexes in references/legacy-modernization/catalog.json plus the generated deprecated-member list
(api/deprecated.tsv, including ambiguous names, which require receiver verification). Findings are REVIEW CANDIDATES
(text matching can hit comments/strings), not proof. Nothing is modified.

  python tools/scan_legacy.py path/to/project_or_file.luau [--json] [--no-api]
"""
from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
csv.field_size_limit(10_000_000)


def load_rules(use_api: bool) -> list[tuple[str, re.Pattern, str]]:
    data = json.loads((ROOT / "references" / "legacy-modernization" / "catalog.json").read_text(encoding="utf-8"))
    rules = [(e["id"], re.compile(e["detect"]), e["new"]) for e in data["entries"] if e.get("detect")]
    if use_api:
        # Every pinned row produces a lexical review candidate, including shared names.
        # This is detection coverage, never receiver-type proof or an automatic rewrite.
        import api
        import classify_legacy
        rules.extend(classify_legacy.generic_rule(row) for row in api.rows("deprecated.tsv"))
    return rules


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("project", type=Path, help="directory (scanned recursively) or a single .lua/.luau file")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--no-api", action="store_true", help="only curated catalog rules")
    a = ap.parse_args()
    if not a.project.exists():
        ap.error(f"not found: {a.project}")
    rules = load_rules(not a.no_api)
    findings = []
    base = a.project if a.project.is_dir() else a.project.parent
    paths = sorted(a.project.rglob("*")) if a.project.is_dir() else [a.project]
    for path in paths:
        if path.suffix not in (".lua", ".luau") or not path.is_file() or ".git" in path.parts:
            continue
        for n, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            if line.lstrip().startswith("--"):
                continue
            hits = [(rid, fix) for rid, rx, fix in rules if rx.search(line)]
            api_candidates = [rid.removeprefix("api-deprecated:") for rid, _ in hits if rid.startswith("api-deprecated:")]
            # Keep one explanation family per line, but retain every generic candidate as
            # machine-readable metadata. A curated hit must not erase another API on the line.
            if any(not rid.startswith("api-deprecated:") for rid, _ in hits):
                hits = [(rid, fix) for rid, fix in hits if not rid.startswith("api-deprecated:")]
            for rid, fix in hits:
                findings.append({"file": path.relative_to(base).as_posix(), "line": n, "rule": rid,
                                 "code": line.strip()[:160], "suggest": fix, "api_candidates": api_candidates})
    if a.json:
        print(json.dumps({"read_only": True, "findings": findings}, indent=1))
    else:
        for f in findings:
            print(f"{f['file']}:{f['line']}: [{f['rule']}] {f['code']}\n    → {f['suggest']}")
        print(f"{len(findings)} candidate(s). Review each; see references/legacy-modernization/CATALOG.md")
    return 0


if __name__ == "__main__":
    sys.exit(main())
