#!/usr/bin/env python3
"""Validate Roblox API references in skill Markdown and Luau files against the generated api/ index.

Checks
  - `Class.Member` / `Class:Method` where Class is a real engine class: member must exist (inheritance resolved)
  - `Enum.Type` / `Enum.Type.Item`: must exist
  - library/datatype calls (`task.wait`, `buffer.readbits`, `RaycastParams.new`, `vector.create`...): must exist
  - `GetService("X")`: X must be a service;  `Instance.new("X")`: X must exist and be creatable
  - deprecated/superseded references outside an explicit legacy context
  - assignments to properties that game scripts cannot write (`Lighting.LightingStyle = ...`, `.Technology = ...`)

Context markers (line or first line of a fenced block):
  BAD / LEGACY / OLD / deprecated / superseded / → / ->   allow deprecated refs and restricted writes on that line/block
  FAKE / HALLUCINATED / does not exist / api-ignore         allow unknown APIs on that line/block
Files under references/legacy-modernization/, references/ai-failure-modes.md, references/anti-patterns.md,
maintainers/ and evals/ are legacy contexts by design (unknown refs still need FAKE markers).

  python tools/check_api_refs.py            check the whole skill
  python tools/check_api_refs.py FILE...    check specific files
"""
from __future__ import annotations

import csv
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import api  # noqa: E402

SKIP_DIRS = {".cache", ".git", "api", "node_modules", "__pycache__"}
LEGACY_FILES = ("references/legacy-modernization/", "references/ai-failure-modes.md", "references/anti-patterns.md",
                "maintainers/", "evals/")
LEGACY_MARK = re.compile(r"\bBAD\b|\bLEGACY\b|\bOLD\b|deprecated|superseded|→|->|❌|\bwas\b|\bformerly\b", re.I)
FAKE_MARK = re.compile(r"\bFAKE\b|HALLUCINATED|does not exist|doesn't exist|api-ignore|not a real|invented|"
                       r"not available|unavailable|\babsent\b|\bno `|removed|never existed", re.I)
FOLDER_SERVICES = {"ReplicatedStorage", "ServerStorage", "ServerScriptService", "ReplicatedFirst", "StarterGui",
                   "StarterPack", "StarterPlayerScripts", "StarterCharacterScripts", "PlayerGui", "Backpack",
                   "PlayerScripts"}
LIBS = {"task", "buffer", "vector", "math", "table", "string", "coroutine", "bit32", "utf8", "os", "debug"}

REF = re.compile(r"(?<![\w.])([A-Z][A-Za-z0-9]*|task|buffer|vector|math|table|string|coroutine|bit32|utf8|os|debug)"
                 r"([.:])([A-Za-z_][A-Za-z0-9_]*)(?:\.([A-Za-z_][A-Za-z0-9_]*))?")
SERVICE = re.compile(r"GetService\(\s*[\"'](\w+)[\"']\s*\)")
NEW = re.compile(r"Instance\.new\(\s*[\"'](\w+)[\"']")
ASSIGN = re.compile(r"\.([A-Za-z_]\w*)\s*=(?!=)")

csv.field_size_limit(10_000_000)


def restricted_props() -> dict[str, str]:
    """Property names that no class lets game scripts write (so any assignment is wrong)."""
    per_name: dict[str, list[bool]] = {}
    for cls, ms in api.members().items():
        for name, m in ms.items():
            if m["kind"] != "Property":
                continue
            flags = m["flags"]
            blocked = (m["write"] != "None" or "write:plugin-only" in flags or "notscriptable" in flags
                       or "readonly" in flags)
            per_name.setdefault(name, []).append(blocked)
    return {n: "not writable by game scripts" for n, v in per_name.items() if all(v) and len(n) > 3}


def datatype_owners() -> set[str]:
    return {r["owner"] for r in api.datatypes().values()}


def check_line(text: str, ctx_legacy: bool, ctx_fake: bool, in_code: bool, restricted: dict[str, str],
               dt_owners: set[str]) -> list[tuple[str, str]]:
    out = []
    legacy = ctx_legacy or bool(LEGACY_MARK.search(text))
    fake = ctx_fake or bool(FAKE_MARK.search(text))
    for m in SERVICE.finditer(text):
        name = m.group(1)
        c = api.classes().get(name)
        if not c and not fake:
            out.append(("error", f"GetService(\"{name}\"): no such class"))
        elif c and "service" not in c["tags"] and not fake:
            out.append(("error", f"GetService(\"{name}\"): {name} is not a service"))
    for m in NEW.finditer(text):
        name = m.group(1)
        c = api.classes().get(name)
        if not c:
            if not fake:
                out.append(("error", f"Instance.new(\"{name}\"): no such class"))
        elif "notcreatable" in c["tags"] and not fake:
            out.append(("error", f"Instance.new(\"{name}\"): class is NotCreatable"))
        elif "deprecated" in c["tags"] and not legacy:
            out.append(("warn", f"Instance.new(\"{name}\"): deprecated class"))
    for m in REF.finditer(text):
        owner, sep, member, sub = m.group(1), m.group(2), m.group(3), m.group(4)
        if owner == "Enum":
            e = api.enums().get(member)
            if e is None:
                if not fake:
                    out.append(("error", f"Enum.{member}: no such enum"))
            elif sub:
                item = e.get(sub)
                if item is None and sub not in ("Value", "Name", "EnumType", "GetEnumItems", "FromName", "FromValue"):
                    if not fake:
                        out.append(("error", f"Enum.{member}.{sub}: no such item"))
                elif item is not None and "deprecated" in item["flags"] and not legacy:
                    out.append(("warn", f"Enum.{member}.{sub}: deprecated item"))
            continue
        if owner in api.classes():
            if member in ("new",) and owner not in dt_owners:
                continue  # user modules often shadow class names (e.g. a local Camera module)
            found = api.resolve_member(owner, member)
            if found is None and owner in FOLDER_SERVICES:
                continue  # user hierarchy path, e.g. ReplicatedStorage.Remotes
            if found is None and member in api.classes():
                continue  # hierarchy path to a child container, e.g. Player.PlayerGui, StarterPlayer.StarterPlayerScripts
            if found is None:
                key = f"{owner}.{member}"
                if key in api.datatypes() or owner in dt_owners:
                    continue
                if not fake:
                    out.append(("error", f"{owner}{sep}{member}: not a member of {owner} (or superclasses)"))
                continue
            _, row = found
            if ("deprecated" in row["flags"] or "superseded" in row["flags"]) and not legacy:
                out.append(("warn", f"{owner}{sep}{member}: deprecated/superseded ({row['flags']})"))
            continue
        if owner in LIBS or owner in dt_owners:
            key = f"{owner}.{member}"
            if owner in LIBS and owner not in ("math", "table", "string", "os", "debug", "coroutine", "utf8"):
                pass
            dt = api.datatypes().get(key)
            if dt is None:
                # Methods/properties on datatype instances are also stored as Owner.member / Owner:member.
                if f"{owner}:{member}" in api.datatypes():
                    continue
                if owner in ("math", "table", "string", "os", "debug", "coroutine", "utf8", "bit32", "task",
                             "buffer", "vector") and not fake:
                    out.append(("error", f"{key}: not in the Roblox {owner} library"))
                continue
            if ("deprecated" in dt["flags"] or "superseded" in dt["flags"]) and not legacy:
                out.append(("warn", f"{key}: deprecated/superseded"))
    if in_code and not legacy:
        for m in ASSIGN.finditer(text):
            prop = m.group(1)
            if prop in restricted:
                out.append(("error", f"assignment to .{prop}: {restricted[prop]} (Studio/plugin setting)"))
    # Deprecated globals in code.
    if in_code and not legacy:
        for g in ("wait", "spawn", "delay"):
            if re.search(r"(?<![\w.:])" + g + r"\s*\(", text):
                out.append(("warn", f"{g}(): deprecated global, use task.{g}"))
    return out


def rel_of(path: Path) -> str:
    try:
        return path.relative_to(ROOT).as_posix()
    except ValueError:
        return path.as_posix()


def iter_files(paths: list[str]) -> list[Path]:
    if paths:
        return [Path(p).resolve() for p in paths]
    files = []
    for p in ROOT.rglob("*"):
        if p.is_file() and p.suffix in (".md", ".luau") and not (set(p.relative_to(ROOT).parts) & SKIP_DIRS):
            files.append(p)
    return sorted(files)


def check_file(path: Path, restricted: dict[str, str], dt_owners: set[str]) -> list[tuple[int, str, str]]:
    rel = rel_of(path)
    file_legacy = rel.startswith(LEGACY_FILES)
    lines = path.read_text(encoding="utf-8").splitlines()
    findings = []
    if path.suffix == ".luau":
        head = "\n".join(lines[:5])
        blk_legacy = file_legacy or bool(re.search(r"--\s*(BAD|LEGACY)", head))
        blk_fake = bool(FAKE_MARK.search(head))
        for i, line in enumerate(lines, 1):
            code = line
            for sev, msg in check_line(code, blk_legacy, blk_fake, True, restricted, dt_owners):
                findings.append((i, sev, msg))
        return findings
    in_code = False
    blk_legacy = blk_fake = False
    fence_lang = ""
    for i, line in enumerate(lines, 1):
        stripped = line.strip()
        if stripped.startswith("```"):
            if not in_code:
                in_code = True
                fence_lang = stripped[3:].strip().lower()
                blk_legacy = blk_fake = False
                # Look ahead at the first 2 lines of the block for context markers.
                look = " ".join(lines[i:i + 2])
                blk_legacy = bool(re.search(r"\b(BAD|LEGACY|OLD)\b", look))
                blk_fake = bool(FAKE_MARK.search(look))
            else:
                in_code = False
            continue
        if in_code:
            if fence_lang not in ("lua", "luau", ""):
                continue
            for sev, msg in check_line(line, file_legacy or blk_legacy, blk_fake, True, restricted, dt_owners):
                findings.append((i, sev, msg))
        else:
            spans = re.findall(r"`([^`]+)`", line)
            for span in spans:
                for sev, msg in check_line(span, file_legacy or bool(LEGACY_MARK.search(line)),
                                           bool(FAKE_MARK.search(line)), False, restricted, dt_owners):
                    findings.append((i, sev, msg))
    return findings


def main(argv: list[str]) -> int:
    restricted = restricted_props()
    dt_owners = datatype_owners()
    errors = warns = 0
    for path in iter_files(argv):
        for line, sev, msg in check_file(path, restricted, dt_owners):
            rel = rel_of(path)
            print(f"{rel}:{line}: {sev}: {msg}")
            if sev == "error":
                errors += 1
            else:
                warns += 1
    print(f"api-refs: {errors} error(s), {warns} warning(s)")
    return 1 if errors or warns else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
