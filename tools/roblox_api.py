#!/usr/bin/env python3
"""Offline Roblox Engine API lookup (classes, members, inheritance, enums, datatypes, globals).

Data: reference/roblox-api/globalTypes.d.luau (luau-lsp generated type definitions, MIT) and
reference/roblox-api/api-summaries.json.gz (one-line official member summaries). A newer copy in
.toolchain/ (tools/setup_luau_toolchain.sh) is preferred when present.

Examples:
  python tools/roblox_api.py Humanoid                 # class: chain + own members
  python tools/roblox_api.py Humanoid --all           # include inherited members
  python tools/roblox_api.py Humanoid.MoveTo          # member (searches ancestors), doc, deprecation
  python tools/roblox_api.py Enum.HumanoidStateType   # enum items
  python tools/roblox_api.py CFrame                   # datatype constructors + members
  python tools/roblox_api.py task                     # global library
  python tools/roblox_api.py --find Raycast           # every Class.Member containing text

Only what the definitions file declares is shown: members hidden by security (RobloxScriptSecurity etc.)
are absent. Absence here is strong evidence, not proof; check create.roblox.com for new/beta APIs.
"""
from __future__ import annotations

import argparse
import gzip
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEF_CANDIDATES = [ROOT / ".toolchain" / "globalTypes.d.luau", ROOT / "reference" / "roblox-api" / "globalTypes.d.luau"]
DOCS = ROOT / "reference" / "roblox-api" / "api-summaries.json.gz"

HEADER = re.compile(r"^declare extern type (\w+)(?: extends (\w+))? with\s*$")
GLOBAL_TABLE = re.compile(r"^declare (\w+): \{\s*$")
GLOBAL_LINE = re.compile(r"^declare (?:function )?(\w+)")
MEMBER_FN = re.compile(r"^function (\w+)\((.*)$")
MEMBER_PROP = re.compile(r"^(\w+): (.+)$")


@dataclass
class Member:
    name: str
    kind: str  # property | method | event | callback
    decl: str
    deprecated: str | None = None


@dataclass
class TypeDecl:
    name: str
    parent: str | None
    members: dict[str, Member] = field(default_factory=dict)


def load_defs() -> tuple[dict[str, TypeDecl], dict[str, list[str]], dict[str, str], Path]:
    path = next((p for p in DEF_CANDIDATES if p.exists()), None)
    if path is None:
        sys.exit("No globalTypes.d.luau found. Run tools/setup_luau_toolchain.sh")
    types: dict[str, TypeDecl] = {}
    tables: dict[str, list[str]] = {}
    globals_: dict[str, str] = {}
    lines = path.read_text(encoding="utf-8").splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        m = HEADER.match(line)
        if m:
            decl = TypeDecl(m.group(1), m.group(2))
            pending_dep: str | None = None
            i += 1
            while i < len(lines) and lines[i].strip() != "end":
                raw = lines[i].strip()
                if raw.startswith("@"):
                    dm = re.search(r'use\s*=\s*"([^"]+)"', raw)
                    pending_dep = dm.group(1) if dm else "deprecated"
                elif raw:
                    fm = MEMBER_FN.match(raw)
                    pm = MEMBER_PROP.match(raw)
                    if fm:
                        mem = Member(fm.group(1), "method", raw, pending_dep)
                    elif pm:
                        t = pm.group(2)
                        kind = "event" if t.startswith("RBXScriptSignal") else ("callback" if "->" in t and t.startswith("(") else "property")
                        mem = Member(pm.group(1), kind, raw, pending_dep)
                    else:
                        mem = None
                    if mem:
                        decl.members.setdefault(mem.name, mem)
                    pending_dep = None
                i += 1
            types[decl.name] = decl
        else:
            g = GLOBAL_TABLE.match(line)
            if g:
                body = []
                i += 1
                while i < len(lines) and not lines[i].startswith("}"):
                    body.append(lines[i].strip())
                    i += 1
                tables[g.group(1)] = body
            else:
                gl = GLOBAL_LINE.match(line)
                if gl and gl.group(1) not in ("extern", "class"):
                    globals_.setdefault(gl.group(1), line)
        i += 1
    return types, tables, globals_, path


def load_docs() -> dict[str, str]:
    if not DOCS.exists():
        return {}
    with gzip.open(DOCS, "rt", encoding="utf-8") as f:
        return json.load(f)


def chain(types: dict[str, TypeDecl], name: str) -> list[str]:
    out = []
    while name and name in types and name not in out:
        out.append(name)
        name = types[name].parent or ""
    return out


def clean(doc: str) -> str:
    doc = re.sub(r"<[^>]+>", "", doc)
    return doc.replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", "&").replace("&quot;", '"')


def fmt_member(m: Member, owner: str, docs: dict[str, str]) -> str:
    s = f"  [{m.kind}] {m.decl}"
    if m.deprecated:
        s += f"\n      DEPRECATED -> use {m.deprecated}"
    doc = docs.get(f"{owner}.{m.name}")
    if doc:
        s += f"\n      {clean(doc).splitlines()[0][:300]}"
    return s


def show_enum(types, name: str) -> int:
    internal = types.get(f"Enum{name}_INTERNAL")
    if internal is None:
        print(f"Enum.{name}: not declared")
        return 1
    print(f"Enum.{name} items:")
    for m in internal.members.values():
        if m.kind == "property":
            print(f"  Enum.{name}.{m.name}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("query", nargs="?")
    ap.add_argument("--all", action="store_true", help="include inherited members")
    ap.add_argument("--find", metavar="TEXT", help="search Class.Member names (case-insensitive)")
    ap.add_argument("--no-docs", action="store_true")
    args = ap.parse_args()
    types, tables, globals_, path = load_defs()
    docs = {} if args.no_docs else load_docs()

    if args.find:
        needle = args.find.lower()
        hits = 0
        for tname, t in sorted(types.items()):
            if tname.startswith("Enum") and tname.endswith("_INTERNAL"):
                for m in t.members:
                    if needle in m.lower() or needle in tname.lower():
                        print(f"Enum.{tname[4:-9]}.{m}")
                        hits += 1
                continue
            if tname.startswith("Enum"):
                continue
            for m in t.members.values():
                if needle in m.name.lower():
                    print(f"{tname}.{m.name}  [{m.kind}]" + (f"  DEPRECATED -> {m.deprecated}" if m.deprecated else ""))
                    hits += 1
        for g, body in tables.items():
            for b in body:
                if needle in b.lower():
                    print(f"{g}: {b}")
                    hits += 1
        print(f"-- {hits} hits in {path.relative_to(ROOT)}")
        return 0 if hits else 1

    if not args.query:
        ap.print_help()
        return 2
    q = args.query.strip().replace(":", ".")
    if q.startswith("Enum."):
        return show_enum(types, q.split(".")[1])

    owner, _, member = q.partition(".")
    if owner in types and not member:
        t = types[owner]
        ch = chain(types, owner)
        print(f"{owner}  (inherits: {' -> '.join(ch[1:]) or '-'})")
        if docs.get(owner):
            print(f"  {clean(docs[owner]).splitlines()[0][:400]}")
        if owner in tables:
            print("  constructors / static:")
            for b in tables[owner]:
                print(f"    {b}")
        for cname in (ch if args.all else ch[:1]):
            c = types[cname]
            if args.all:
                print(f"-- from {cname}")
            for kind in ("property", "method", "event", "callback"):
                for m in sorted(c.members.values(), key=lambda x: x.name):
                    if m.kind == kind and (m.name[0].isupper() or m.deprecated is None):
                        print(fmt_member(m, cname, docs))
        if not args.all and len(ch) > 1:
            print(f"-- plus inherited members from {', '.join(ch[1:])} (use --all)")
        return 0
    if owner in types and member:
        for cname in chain(types, owner):
            m = types[cname].members.get(member)
            if m:
                print(f"{owner}.{member}" + (f"  (declared on {cname})" if cname != owner else ""))
                print(fmt_member(m, cname, docs))
                return 0
        static = [b for b in tables.get(owner, []) if b.startswith(member + ":")]
        if static:
            for b in static:
                print(f"{owner}.{b}  (static/constructor)")
            return 0
        close = [n for c in chain(types, owner) for n in types[c].members if n.lower() == member.lower() or member.lower() in n.lower()]
        print(f"{owner}.{member}: NOT declared on {owner} or its ancestors. Similar: {sorted(set(close))[:15]}")
        return 1
    if owner in tables:
        body = tables[owner]
        if member:
            hits = [b for b in body if b.startswith(member + ":")]
            for b in hits:
                print(f"{owner}.{b}")
            if not hits:
                print(f"{owner}.{member}: not declared")
                return 1
        else:
            print(f"{owner}:")
            for b in body:
                print(f"  {b}")
        return 0
    if owner in globals_:
        print(globals_[owner])
        return 0
    print(f"{q}: unknown class/global. Try --find {owner}")
    return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BrokenPipeError:
        sys.exit(0)
