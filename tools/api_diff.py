#!/usr/bin/env python3
"""What changed in the engine API index? Compares api/*.tsv in the working tree with a git revision.

Run after `fetch_sources.py --latest && build_api_index.py` to see what to review in the handbook/catalog:
new/removed classes and members, newly deprecated or superseded members, security/capability changes,
members that became documented or undocumented.

  python tools/api_diff.py              compare with HEAD
  python tools/api_diff.py --rev v2.0.0
"""
from __future__ import annotations

import argparse
import csv
import io
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
csv.field_size_limit(10_000_000)


def rows(text: str) -> list[dict]:
    return list(csv.DictReader(io.StringIO(text), delimiter="\t", quoting=csv.QUOTE_NONE))


def at_rev(rev: str, rel: str) -> str:
    res = subprocess.run(["git", "show", f"{rev}:{rel}"], cwd=ROOT, capture_output=True, text=True)
    if res.returncode != 0:
        sys.exit(f"cannot read {rel} at {rev}: {res.stderr.strip()}")
    return res.stdout


def members(text: str) -> dict[str, dict]:
    return {f"{r['class']}.{r['member']}": r for r in rows(text)}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--rev", default="HEAD")
    ap.add_argument("--limit", type=int, default=60, help="max lines per section")
    a = ap.parse_args()
    old_c = {r["class"]: r for r in rows(at_rev(a.rev, "api/classes.tsv"))}
    new_c = {r["class"]: r for r in rows((ROOT / "api" / "classes.tsv").read_text(encoding="utf-8"))}
    old_m = members(at_rev(a.rev, "api/members.tsv"))
    new_m = members((ROOT / "api" / "members.tsv").read_text(encoding="utf-8"))

    def flags(r: dict) -> set[str]:
        return {f for f in r.get("flags", "").split(",") if f}

    sections: dict[str, list[str]] = {
        "new classes": sorted(set(new_c) - set(old_c)),
        "removed classes": sorted(set(old_c) - set(new_c)),
        "new members": sorted(set(new_m) - set(old_m)),
        "removed members": sorted(set(old_m) - set(new_m)),
        "newly deprecated/superseded": [], "security or capability changes": [],
        "became documented": [], "became undocumented": [],
    }
    for key in sorted(set(old_m) & set(new_m)):
        o, n = old_m[key], new_m[key]
        fo, fn = flags(o), flags(n)
        if ({"deprecated", "superseded"} & fn) - ({"deprecated", "superseded"} & fo):
            sections["newly deprecated/superseded"].append(key)
        caps_o = {f for f in fo if f.startswith(("cap=", "read:", "write:", "call:"))}
        caps_n = {f for f in fn if f.startswith(("cap=", "read:", "write:", "call:"))}
        if (o["read"], o["write"]) != (n["read"], n["write"]) or caps_o != caps_n:
            sections["security or capability changes"].append(
                f"{key}: {o['read']}/{o['write']} {sorted(caps_o)} -> {n['read']}/{n['write']} {sorted(caps_n)}")
        if "undocumented" in fo and "undocumented" not in fn:
            sections["became documented"].append(key)
        if "undocumented" in fn and "undocumented" not in fo:
            sections["became undocumented"].append(key)
    total = 0
    for title, items in sections.items():
        if not items:
            continue
        total += len(items)
        print(f"## {title} ({len(items)})")
        for item in items[: a.limit]:
            print("  " + item)
        if len(items) > a.limit:
            print(f"  … {len(items) - a.limit} more")
    if total == 0:
        print(f"no API index changes vs {a.rev}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BrokenPipeError:
        sys.exit(0)
