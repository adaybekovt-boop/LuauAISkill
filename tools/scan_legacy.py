#!/usr/bin/env python3
"""Read-only scan of a Roblox/Luau project for legacy/deprecated/unsafe patterns.

Uses the curated regexes in references/legacy-modernization/catalog.json plus the generated deprecated-member list
(api/deprecated.tsv, for `:Method(` / `.Property` names that are unambiguous). Findings are REVIEW CANDIDATES
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
csv.field_size_limit(10_000_000)


def load_rules(use_api: bool) -> list[tuple[str, re.Pattern, str]]:
    data = json.loads((ROOT / "references" / "legacy-modernization" / "catalog.json").read_text(encoding="utf-8"))
    rules = [(e["id"], re.compile(e["detect"]), e["new"]) for e in data["entries"] if e.get("detect")]
    if use_api:
        # Deprecated member names that don't collide with non-deprecated members of other classes.
        live, dead = set(), {}
        with (ROOT / "api" / "members.tsv").open(encoding="utf-8") as f:
            for r in csv.DictReader(f, delimiter="\t", quoting=csv.QUOTE_NONE):
                (dead.setdefault(r["member"], r) if "deprecated" in r["flags"] else live.add(r["member"]))
        for name, r in dead.items():
            if name in live or len(name) < 6 or not name[0].isupper():
                continue
            pref = next((f[7:] for f in r["flags"].split(",") if f.startswith("prefer=")), "see api/deprecated.tsv")
            sep = ":" if r["kind"] in ("Function",) else "."
            rules.append((f"api-deprecated:{r['class']}.{name}", re.compile(re.escape(sep + name) + r"\b"), pref))
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
            # A curated catalog rule already explains the line; the generic API-deprecation hit would repeat it.
            if any(not rid.startswith("api-deprecated:") for rid, _ in hits):
                hits = [(rid, fix) for rid, fix in hits if not rid.startswith("api-deprecated:")]
            for rid, fix in hits:
                findings.append({"file": path.relative_to(base).as_posix(), "line": n, "rule": rid,
                                 "code": line.strip()[:160], "suggest": fix})
    if a.json:
        print(json.dumps({"read_only": True, "findings": findings}, indent=1))
    else:
        for f in findings:
            print(f"{f['file']}:{f['line']}: [{f['rule']}] {f['code']}\n    → {f['suggest']}")
        print(f"{len(findings)} candidate(s). Review each; see references/legacy-modernization/CATALOG.md")
    return 0


if __name__ == "__main__":
    sys.exit(main())
