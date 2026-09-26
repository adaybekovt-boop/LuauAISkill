#!/usr/bin/env python3
"""Validate every source reference in the skill and (re)build sources/registry.json.

Reference syntax used in docs ("Sources:" lines, catalog.json "verify" fields):
  cd:<path>     Roblox creator-docs page/YAML, path relative to content/en-us (no extension)
                -> https://create.roblox.com/docs/<path>
  luau:<path>   luau.org documentation source, relative to src/content/docs (no extension)
  api:<ref>     generated API index entry (Class, Class.Member, Enum.X, datatype/library member)
Each cd:/luau: path must exist in the pinned corpus (.cache/sources, see sources/lock.json); each api: ref must
resolve in api/. Output: sources/registry.json (url, type, pinned commit, retrieval date, cited_by).

  python tools/check_sources.py          validate + write registry
  python tools/check_sources.py --check  validate only (CI)
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import api  # noqa: E402

CD = ROOT / ".cache" / "sources" / "creator-docs" / "content" / "en-us"
LUAU = ROOT / ".cache" / "sources" / "luau-site" / "src" / "content" / "docs"
REF = re.compile(r"\b(cd|luau|api):([A-Za-z0-9_./\-:]+[A-Za-z0-9_])")
SKIP = {".cache", ".git", "api", "node_modules", "qa"}  # qa/ holds generated reports


def resolve_api(ref: str) -> bool:
    ref = ref.replace(":", ".")
    parts = ref.split(".")
    if parts[0] == "Enum":
        e = api.enums().get(parts[1]) if len(parts) > 1 else None
        return e is not None and (len(parts) < 3 or parts[2] in e)
    if ref in api.datatypes() or ref.replace(".", ":", 1) in api.datatypes():
        return True
    if len(parts) == 1:
        return parts[0] in api.classes() or any(r["owner"] == parts[0] for r in api.datatypes().values())
    return parts[0] in api.classes() and api.resolve_member(parts[0], parts[1]) is not None


def resolve(kind: str, path: str) -> tuple[bool, str]:
    if kind == "cd":
        for cand in (CD / f"{path}.md", CD / f"{path}.yaml", CD / path / "index.md"):
            if cand.exists():
                url_path = path[:-6] if path.endswith("/index") else path
                return True, f"https://create.roblox.com/docs/{url_path}"
        return False, ""
    if kind == "luau":
        for cand in (LUAU / f"{path}.md", LUAU / f"{path}.mdx"):
            if cand.exists():
                return True, f"https://github.com/luau-lang/site/blob/{{sha}}/src/content/docs/{cand.relative_to(LUAU).as_posix()}"
        return False, ""
    ok = resolve_api(path)
    return ok, "api/members.tsv (generated from the engine API dump + creator-docs YAML)"


def collect() -> dict[str, set[str]]:
    refs: dict[str, set[str]] = {}
    for p in ROOT.rglob("*"):
        if not p.is_file() or set(p.relative_to(ROOT).parts) & SKIP:
            continue
        if p.suffix not in (".md", ".json", ".luau") or p.name == "registry.json":
            continue
        text = p.read_text(encoding="utf-8", errors="replace")
        for m in REF.finditer(text):
            refs.setdefault(f"{m.group(1)}:{m.group(2)}", set()).add(p.relative_to(ROOT).as_posix())
    return refs


def main() -> int:
    if not CD.exists() or not LUAU.exists():
        print("Corpus missing: python tools/fetch_sources.py", file=sys.stderr)
        return 2
    lock = json.loads((ROOT / "sources" / "lock.json").read_text(encoding="utf-8"))
    refs = collect()
    bad, registry = [], {}
    for ref, files in sorted(refs.items()):
        kind, path = ref.split(":", 1)
        ok, url = resolve(kind, path)
        if not ok:
            bad.append((ref, sorted(files)))
            continue
        src = {"cd": "creator-docs", "luau": "luau-site", "api": "api-dump"}[kind]
        pin = lock["sources"].get(src, {})
        registry[ref] = {
            "url": url.replace("{sha}", pin.get("sha", "")),
            "type": {"cd": "official Roblox documentation", "luau": "official Luau documentation",
                     "api": "generated API index (engine reflection metadata)"}[kind],
            "repo_commit": pin.get("sha", ""),
            "commit_date": pin.get("commit_date", ""),
            "retrieved": lock.get("fetched_on", ""),
            "cited_by": sorted(files),
        }
    for ref, files in bad:
        print(f"UNRESOLVED {ref}  (cited in {', '.join(files[:4])}{' ...' if len(files) > 4 else ''})")
    print(f"sources: {len(registry)} resolved, {len(bad)} unresolved")
    if "--check" not in sys.argv and not bad:
        (ROOT / "sources" / "registry.json").write_text(
            json.dumps({"generated_by": "tools/check_sources.py", "entries": registry}, indent=1) + "\n",
            encoding="utf-8")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
