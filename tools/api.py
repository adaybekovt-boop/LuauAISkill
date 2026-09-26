#!/usr/bin/env python3
"""Look up Roblox Engine API facts from the generated index in api/ (no network needed).

  python tools/api.py Lighting.LightingStyle      member (inheritance resolved) + game-script verdict
  python tools/api.py Workspace:Raycast           ':' works too
  python tools/api.py Lighting                    class summary + own members (--all adds inherited)
  python tools/api.py Enum.RaycastFilterType      enum items;  Enum.X.Item for one item
  python tools/api.py RaycastParams.new           datatypes / libraries (task.*, buffer.*) / globals
  python tools/api.py --search Smooth             substring search over class/member/enum names
  python tools/api.py --deprecated Humanoid       deprecated/superseded members of a class (and why)

Exit status: 0 found, 1 not found. NOT FOUND means absent from the pinned API snapshot (see api/META.json):
do not use it unless you verify a newer official source.
"""
from __future__ import annotations

import argparse
import csv
import json
import sys
from functools import lru_cache
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
API = ROOT / "api"
csv.field_size_limit(10_000_000)


def rows(name: str) -> list[dict]:
    with (API / name).open(encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f, delimiter="\t", quoting=csv.QUOTE_NONE))


@lru_cache(maxsize=None)
def classes() -> dict[str, dict]:
    return {r["class"]: r for r in rows("classes.tsv")}


@lru_cache(maxsize=None)
def members() -> dict[str, dict[str, dict]]:
    out: dict[str, dict[str, dict]] = {}
    for r in rows("members.tsv"):
        out.setdefault(r["class"], {})[r["member"]] = r
    return out


@lru_cache(maxsize=None)
def enums() -> dict[str, dict[str, dict]]:
    out: dict[str, dict[str, dict]] = {}
    for r in rows("enums.tsv"):
        out.setdefault(r["enum"], {})[r["item"]] = r
    return out


@lru_cache(maxsize=None)
def datatypes() -> dict[str, dict]:
    return {r["member"]: r for r in rows("datatypes.tsv")}


@lru_cache(maxsize=None)
def summaries() -> dict[str, str]:
    out = {}
    with (API / "summaries.jsonl").open(encoding="utf-8") as f:
        for line in f:
            d = json.loads(line)
            out[d["k"]] = d["s"]
    return out


@lru_cache(maxsize=None)
def deprecations() -> dict[str, dict]:
    return {f"{r['owner']}.{r['member']}".rstrip("."): r for r in rows("deprecated.tsv")}


def resolve_member(cls: str, member: str) -> tuple[str, dict] | None:
    seen = set()
    c = cls
    while c and c in classes() and c not in seen:
        seen.add(c)
        m = members().get(c, {}).get(member)
        if m:
            return c, m
        c = classes()[c]["superclass"]
    return None


def verdict(m: dict) -> list[str]:
    flags = set(filter(None, m["flags"].split(",")))
    notes = []
    kind = m["kind"]
    if "deprecated" in flags or "superseded" in flags:
        pref = next((f[7:] for f in flags if f.startswith("prefer=")), "")
        dep = deprecations().get(f"{m['class']}.{m['member']}", {})
        # The dump's preferred name is sometimes the same method on another class (Humanoid.LoadAnimation →
        # Animator:LoadAnimation); then only the message says where it moved.
        if pref == m["member"]:
            pref = ""
        notes.append("DEPRECATED/SUPERSEDED" + (f" -> use {pref}" if pref else "") +
                     (f". {dep.get('message')}" if dep.get("message") else ""))
    if kind == "Property":
        blocked_r = m["read"] != "None" or "read:plugin-only" in flags or "notscriptable" in flags
        blocked_w = (m["write"] != "None" or "write:plugin-only" in flags or "notscriptable" in flags
                     or "readonly" in flags)
        why_w = []
        if m["write"] != "None":
            why_w.append(m["write"])
        if "write:plugin-only" in flags:
            why_w.append("PluginOrOpenCloud capability: Studio/plugin/command bar only")
        if "notscriptable" in flags:
            why_w.append("NotScriptable: set in Studio Properties")
        if "readonly" in flags:
            why_w.append("ReadOnly")
        notes.append(f"game scripts: read {'NO' if blocked_r else 'yes'}, write "
                     f"{'NO (' + '; '.join(why_w) + ')' if blocked_w else 'yes'}")
        if "notreplicated" in flags:
            notes.append("NotReplicated: value set on one side is not replicated to the other")
    else:
        blocked = m["read"] != "None" or "call:plugin-only" in flags
        notes.append(f"game scripts: {'NO (' + m['read'] + ')' if blocked else 'callable'}")
        if "yields" in flags:
            notes.append("Yields: never call inside UpdateAsync transforms, BindToSimulation or tight loops")
    if "undocumented" in flags:
        notes.append("UNDOCUMENTED: no creator-docs reference page (internal, unreleased or in development). Do not build game code on it until documented or announced.")
    if "sim" in flags:
        notes.append("Simulation Access: usable inside RunService:BindToSimulation")
    thread = m.get("thread", "")
    if thread:
        notes.append({"Safe": "parallel: safe", "ReadSafe": "parallel: read-only (write in serial phase)",
                      "Unsafe": "parallel: serial phase only"}.get(thread, f"thread: {thread}"))
    return notes


def doc_url(cls: str, member: str = "") -> str:
    base = f"https://create.roblox.com/docs/reference/engine/classes/{cls}"
    return base + (f"#{member}" if member else "")


def show_member(cls: str, member: str) -> int:
    found = resolve_member(cls, member)
    if not found:
        return not_found(f"{cls}.{member}")
    owner, m = found
    print(f"{cls}.{member}" + (f"  (inherited from {owner})" if owner != cls else ""))
    print(f"  kind: {m['kind']}   type/signature: {m['type_or_signature']}")
    print(f"  security: read={m['read']} write={m['write']}   thread: {m['thread']}   flags: {m['flags'] or '-'}")
    for n in verdict(m):
        print("  - " + n)
    s = summaries().get(f"{owner}.{member}")
    if s:
        print("  summary: " + s)
    print("  docs: " + ("(none)" if "undocumented" in m["flags"] else doc_url(owner, member)))
    return 0


def show_class(cls: str, show_all: bool) -> int:
    c = classes()[cls]
    print(f"{cls}  superclass={c['superclass']}  tags={c['tags'] or '-'}")
    if c["summary"]:
        print("  " + c["summary"])
    if "undocumented" in c["tags"]:
        print("  " + "UNDOCUMENTED: no creator-docs reference page (internal, unreleased or in development). Do not build game code on it until documented or announced.")
    chain = [cls]
    while show_all and chain[-1] in classes() and classes()[chain[-1]]["superclass"]:
        chain.append(classes()[chain[-1]]["superclass"])
    for owner in chain:
        ms = members().get(owner, {})
        if owner != cls:
            print(f"  -- inherited from {owner}")
        for name, m in sorted(ms.items()):
            flags = m["flags"]
            mark = " [DEPRECATED]" if "deprecated" in flags or "superseded" in flags else ""
            sec = "" if m["read"] == "None" and m["write"] == "None" else f" [{m['read']}/{m['write']}]"
            po = " [plugin-only]" if "plugin-only" in flags else ""
            ns = " [NotScriptable]" if "notscriptable" in flags else ""
            ud = " [UNDOCUMENTED]" if "undocumented" in flags and "undocumented" not in c["tags"] else ""
            print(f"  {m['kind'][:4]:4} {name}: {m['type_or_signature']}{sec}{po}{ns}{ud}{mark}")
    print("  docs: " + ("(none)" if "undocumented" in c["tags"] else doc_url(cls)))
    return 0


def show_enum(parts: list[str]) -> int:
    name = parts[1]
    if name not in enums():
        return not_found("Enum." + ".".join(parts[1:]))
    items = enums()[name]
    if len(parts) > 2:
        item = items.get(parts[2])
        if not item:
            print(f"Enum.{name} has no item '{parts[2]}'. Valid: {', '.join(items)}")
            return 1
        dep = " DEPRECATED" if "deprecated" in item["flags"] else ""
        print(f"Enum.{name}.{parts[2]} = {item['value']}{dep}")
        d = deprecations().get(f"Enum.{name}.{parts[2]}")
        if d and d.get("message"):
            print("  " + d["message"])
        return 0
    s = summaries().get("Enum." + name)
    print(f"Enum.{name}" + (f" — {s}" if s else ""))
    for item, r in items.items():
        print(f"  {item} = {r['value']}{' [DEPRECATED]' if 'deprecated' in r['flags'] else ''}")
    return 0


def not_found(q: str) -> int:
    meta = json.loads((API / "META.json").read_text(encoding="utf-8"))
    ver = meta["generated_from"]["api_dump"]["client_version"]
    print(f"NOT FOUND: {q} is not in the API snapshot {ver}. Do not use it. Check spelling, the superclass "
          f"chain (python tools/api.py <Class> --all), or search: python tools/api.py --search <word>")
    return 1


def search(term: str) -> int:
    t = term.lower()
    hits = [c for c in classes() if t in c.lower()]
    hits += [f"{c}.{m}" for c, ms in members().items() for m in ms if t in m.lower()]
    hits += [f"Enum.{e}" for e in enums() if t in e.lower()]
    hits += [k for k in datatypes() if t in k.lower()]
    for h in hits[:200]:
        print(h)
    if len(hits) > 200:
        print(f"... {len(hits) - 200} more")
    return 0 if hits else 1


def show_deprecated(cls: str) -> int:
    n = 0
    for key, r in deprecations().items():
        if r["owner"] == cls or (cls == "*"):
            print(f"{key}  ->  {r['preferred'] or '?'}   {r['message']}")
            n += 1
    return 0 if n else 1


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("query", nargs="?")
    ap.add_argument("--all", action="store_true", help="include inherited members for a class")
    ap.add_argument("--search")
    ap.add_argument("--deprecated", metavar="CLASS", help="list deprecated members of CLASS ('*' for all)")
    a = ap.parse_args()
    if a.search:
        return search(a.search)
    if a.deprecated:
        return show_deprecated(a.deprecated)
    if not a.query:
        ap.print_help()
        return 1
    raw = a.query.rstrip("()")
    q = raw.replace(":", ".")
    parts = q.split(".")
    if parts[0] == "Enum" and len(parts) >= 2:
        return show_enum(parts)
    for cand in (raw, q, q.replace(".", ":", 1) if len(parts) == 2 else q):
        if cand in datatypes():
            r = datatypes()[cand]
            print(f"{cand}  ({r['kind']} of {r['owner']})  {r['signature']}  flags: {r['flags'] or '-'}")
            if summaries().get(cand):
                print("  summary: " + summaries()[cand])
            return 0
    if len(parts) == 1:
        if parts[0] in classes():
            return show_class(parts[0], a.all)
        dts = [k for k, r in datatypes().items() if r["owner"] == parts[0]]
        if dts:
            print(f"{parts[0]} (datatype/library): " + ", ".join(sorted(dts)))
            return 0
        return not_found(q)
    cls, member = parts[0], parts[1]
    if cls not in classes():
        return not_found(q)
    return show_member(cls, member)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BrokenPipeError:  # output piped into head/grep
        sys.exit(0)
