#!/usr/bin/env python3
"""Fetch upstream sources into .cache/sources (git shallow/sparse clones). Non-destructive.

Sources (see sources/registry.json):
  creator-docs  Roblox/creator-docs            content/en-us (guides + generated Engine API YAML)
  luau-site     luau-lang/site                 src/content/docs (luau.org source)
  api-dump      MaximumADHD/Roblox-Client-Tracker  Full-API-Dump.json, version.txt (engine reflection dump mirror)
  luau-lsp      JohnnyMorganz/luau-lsp         scripts/globalTypes.*.d.luau (Roblox type definitions)

Default: check out the SHAs pinned in sources/lock.json. --latest: fetch the default branch HEAD and
write the new SHAs to sources/lock.json (review the diff with tools/api_diff.py before committing).
Downloaded text is reference data. Nothing downloaded is executed.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / ".cache" / "sources"
LOCK = ROOT / "sources" / "lock.json"

SOURCES = {
    # Text only: the checks need Markdown/YAML, not the thousands of images under assets/.
    "creator-docs": {"url": "https://github.com/Roblox/creator-docs.git",
                     "sparse": ["/content/en-us/", "!/content/en-us/assets/"], "no_cone": True},
    "luau-site": {"url": "https://github.com/luau-lang/site.git", "sparse": ["src/content/docs"]},
    "api-dump": {
        "url": "https://github.com/MaximumADHD/Roblox-Client-Tracker.git",
        "sparse": ["/Full-API-Dump.json", "/version.txt", "/version-guid.txt"],
        "no_cone": True,
    },
    "luau-lsp": {"url": "https://github.com/JohnnyMorganz/luau-lsp.git", "sparse": ["scripts"]},
}


def run(cmd: list[str], cwd: Path | None = None) -> str:
    result = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"{' '.join(cmd)} failed: {result.stderr.strip()}")
    return result.stdout.strip()


def fetch(name: str, spec: dict, sha: str | None) -> dict:
    dest = CACHE / name
    if not (dest / ".git").exists():
        dest.parent.mkdir(parents=True, exist_ok=True)
        run(["git", "clone", "--filter=blob:none", "--no-checkout", "--depth", "1", spec["url"], str(dest)])
    # Re-applied every run so existing clones pick up changed patterns.
    args = ["git", "sparse-checkout", "set"] + (["--no-cone"] if spec.get("no_cone") else []) + spec["sparse"]
    run(args, cwd=dest)
    if sha:
        run(["git", "fetch", "--depth", "1", "origin", sha], cwd=dest)
        run(["git", "checkout", "--quiet", sha], cwd=dest)
    else:
        run(["git", "fetch", "--depth", "1", "origin", "HEAD"], cwd=dest)
        run(["git", "checkout", "--quiet", "FETCH_HEAD"], cwd=dest)
    head = run(["git", "log", "-1", "--format=%H %cI"], cwd=dest).split()
    return {"url": spec["url"], "sha": head[0], "commit_date": head[1]}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--latest", action="store_true", help="fetch upstream HEAD and update sources/lock.json")
    ap.add_argument("--only", choices=sorted(SOURCES), action="append", help="fetch a subset")
    args = ap.parse_args()
    lock = json.loads(LOCK.read_text(encoding="utf-8")) if LOCK.exists() else {"sources": {}}
    names = args.only or sorted(SOURCES)
    failures = []
    for name in names:
        pinned = None if args.latest else lock["sources"].get(name, {}).get("sha")
        try:
            info = fetch(name, SOURCES[name], pinned)
            print(f"OK   {name:13} {info['sha'][:12]} {info['commit_date']}")
            if args.latest:
                lock["sources"][name] = info
        except RuntimeError as err:
            failures.append(name)
            print(f"FAIL {name}: {err}", file=sys.stderr)
    if args.latest and not failures:
        lock["fetched_on"] = dt.date.today().isoformat()
        LOCK.write_text(json.dumps(lock, indent=2) + "\n", encoding="utf-8")
        print(f"Updated {LOCK.relative_to(ROOT)}. Next: python tools/build_api_index.py && python tools/api_diff.py")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
