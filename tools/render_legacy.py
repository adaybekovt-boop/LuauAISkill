#!/usr/bin/env python3
"""Render references/legacy-modernization/catalog.json → CATALOG.md and validate entries.

Validation: unique ids, known status, detect regexes compile. (Source refs are validated by check_sources.py.)
  python tools/render_legacy.py          write CATALOG.md
  python tools/render_legacy.py --check  fail if CATALOG.md is stale or entries invalid (CI)
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIR = ROOT / "references" / "legacy-modernization"
ORDER = ["scheduling", "language", "instances", "runtime", "security", "physics", "queries", "animation", "players",
         "monetization", "teleport", "data", "rendering", "audio", "ui", "input", "chat", "streaming", "terrain",
         "pathfinding", "camera"]


def render(data: dict) -> str:
    lines = [
        "# Legacy → current: catalog (generated from catalog.json — edit the JSON, then run tools/render_legacy.py)",
        "",
        f"API snapshot {data['api_snapshot']}, creator-docs `{data['docs_commit'][:12]}`, checked {data['checked_on']}. "
        "Statuses: " + "; ".join(f"**{k}** = {v}" for k, v in data["status_legend"].items()) + ".",
        "",
        "Scan a project for these patterns: `python tools/scan_legacy.py <project-dir>`. For any other API run "
        "`python tools/api.py Class.Member` (the full deprecated list is `api/deprecated.tsv`).",
        "",
    ]
    by_cat: dict[str, list[dict]] = {}
    for e in data["entries"]:
        by_cat.setdefault(e["category"], []).append(e)
    for cat in ORDER + sorted(set(by_cat) - set(ORDER)):
        if cat not in by_cat:
            continue
        lines += [f"## {cat}", ""]
        for e in by_cat[cat]:
            lines.append(f"### `{e['id']}` — {e['status']}" + (f" (seen {e['era']})" if e.get("era") else ""))
            lines.append(f"- OLD: `{e['old']}`" if "\n" not in e["old"] else "- OLD:\n```text\n" + e["old"] + "\n```")
            lines.append(f"- NEW: `{e['new']}`" if "\n" not in e["new"] else "- NEW:\n```text\n" + e["new"] + "\n```")
            lines.append(f"- WHY: {e['why']}")
            if e.get("when_ok"):
                lines.append(f"- OLD STILL OK WHEN: {e['when_ok']}")
            if e.get("notes"):
                lines.append(f"- NOTES: {e['notes']}")
            if e.get("verify"):
                lines.append("- VERIFY: " + ", ".join(e["verify"]))
            lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def validate(data: dict) -> list[str]:
    errs, seen = [], set()
    for e in data["entries"]:
        if e["id"] in seen:
            errs.append(f"duplicate id {e['id']}")
        seen.add(e["id"])
        if e["status"] not in data["status_legend"]:
            errs.append(f"{e['id']}: unknown status {e['status']}")
        if e.get("detect"):
            try:
                re.compile(e["detect"])
            except re.error as err:
                errs.append(f"{e['id']}: bad regex {err}")
        for field in ("old", "new", "why"):
            if not e.get(field):
                errs.append(f"{e['id']}: missing {field}")
    return errs


def main() -> int:
    data = json.loads((DIR / "catalog.json").read_text(encoding="utf-8"))
    errs = validate(data)
    for e in errs:
        print("ERROR", e)
    out = render(data)
    target = DIR / "CATALOG.md"
    if "--check" in sys.argv:
        if not target.exists() or target.read_text(encoding="utf-8") != out:
            print("CATALOG.md is stale: run python tools/render_legacy.py")
            return 1
    else:
        target.write_text(out, encoding="utf-8")
    print(f"legacy catalog: {len(data['entries'])} entries, {len(errs)} error(s)")
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main())
