#!/usr/bin/env python3
"""Build the machine-friendly API index in api/ from fetched upstream sources.

Inputs (fetch with tools/fetch_sources.py):
  .cache/sources/api-dump/Full-API-Dump.json               reflection metadata (security, tags, thread safety)
  .cache/sources/creator-docs/content/en-us/reference/engine  official generated YAML (summaries, deprecation text,
                                                            datatypes, libraries, globals, simulationAccess)
Outputs (committed, grep-friendly, regenerate instead of hand-editing):
  api/META.json  api/classes.tsv  api/members.tsv  api/enums.tsv  api/datatypes.tsv  api/deprecated.tsv
  api/summaries.jsonl
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import yaml

try:
    Loader = yaml.CSafeLoader
except AttributeError:  # pragma: no cover
    Loader = yaml.SafeLoader

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / ".cache" / "sources"
DUMP = SRC / "api-dump" / "Full-API-Dump.json"
REF = SRC / "creator-docs" / "content" / "en-us" / "reference" / "engine"
OUT = ROOT / "api"

LINK = re.compile(r"`(?:Class|Enum|Datatype|Global|Library)\.([^`|]+)(?:\|([^`]+))?`")


def clean(text: str | None, limit: int = 240) -> str:
    if not text:
        return ""
    text = LINK.sub(lambda m: "`" + m.group(1) + "`", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text if len(text) <= limit else text[: limit - 1].rstrip() + "…"


def type_name(t: dict | list | None) -> str:
    if not t:
        return ""
    if isinstance(t, list):  # tuple returns
        return "(" + ", ".join(type_name(x) for x in t) + ")"
    return t.get("Name", "")


def signature(m: dict) -> str:
    kind = m["MemberType"]
    if kind == "Property":
        return type_name(m.get("ValueType"))
    params = []
    for p in m.get("Parameters", []):
        s = f"{p['Name']}: {type_name(p['Type'])}"
        if "Default" in p:
            d = str(p["Default"])
            s += f" = {d if len(d) <= 24 else '…'}"
        params.append(s)
    sig = "(" + ", ".join(params) + ")"
    if kind in ("Function", "Callback"):
        ret = type_name(m.get("ReturnType"))
        sig += " -> " + (ret if ret and ret != "null" else "()")
    return sig


def flags_for(m: dict) -> list[str]:
    out = []
    for tag in m.get("Tags") or []:
        if isinstance(tag, dict):
            if "PreferredDescriptorName" in tag:
                out.append("prefer=" + tag["PreferredDescriptorName"])
        else:
            out.append(tag.lower())
    if m.get("SimulationAccess"):
        out.append("sim")
    caps = m.get("Capabilities")
    # PluginOrOpenCloud = callable only from Studio plugins / command bar / Open Cloud Luau, never from game scripts.
    if isinstance(caps, dict):  # properties: {"Read": [...], "Write": [...]}
        if "PluginOrOpenCloud" in caps.get("Read", []):
            out.append("read:plugin-only")
        if "PluginOrOpenCloud" in caps.get("Write", []):
            out.append("write:plugin-only")
        names = sorted({c for v in caps.values() for c in v} - {"PluginOrOpenCloud"})
        if names:
            out.append("cap=" + "|".join(names))
    elif caps:
        if "PluginOrOpenCloud" in caps:
            out.append("call:plugin-only")
        names = [c for c in caps if c != "PluginOrOpenCloud"]
        if names:
            out.append("cap=" + "|".join(names))
    return out


def security(m: dict) -> tuple[str, str]:
    sec = m.get("Security", "None")
    if isinstance(sec, dict):
        return sec.get("Read", "None"), sec.get("Write", "None")
    return sec, sec


def load_yaml(path: Path) -> dict:
    return yaml.load(path.read_text(encoding="utf-8"), Loader=Loader) or {}


def main() -> int:
    if not DUMP.exists() or not REF.exists():
        print("Sources missing. Run: python tools/fetch_sources.py", file=sys.stderr)
        return 2
    OUT.mkdir(exist_ok=True)
    dump = json.loads(DUMP.read_text(encoding="utf-8"))
    lock = json.loads((ROOT / "sources" / "lock.json").read_text(encoding="utf-8"))
    version = (SRC / "api-dump" / "version.txt").read_text().strip()
    studio_version = (REF / "STUDIO_VERSION").read_text().strip() if (REF / "STUDIO_VERSION").exists() else ""

    # Official YAML: summaries, deprecation messages, simulationAccess.
    docs: dict[str, dict] = {}
    class_docs: dict[str, dict] = {}
    for path in sorted((REF / "classes").glob("*.yaml")):
        data = load_yaml(path)
        name = data.get("name", path.stem)
        class_docs[name] = {"summary": clean(data.get("summary")), "dep": clean(data.get("deprecation_message"), 400)}
        for section in ("properties", "methods", "events", "callbacks"):
            for m in data.get(section) or []:
                key = m["name"].replace(":", ".")
                desc = m.get("description") or ""
                superseded = bool(re.search(r"has been superseded|is superseded|been deprecated|should not be used for (new|future) work|deprecated in favor", desc, re.I))
                docs[key] = {
                    "summary": clean(m.get("summary")),
                    "dep": clean(m.get("deprecation_message"), 400),
                    "superseded_hint": clean(desc, 400) if superseded and not m.get("deprecation_message") else "",
                }

    classes_rows, member_rows, summaries, dep_rows = [], [], [], []
    for c in sorted(dump["Classes"], key=lambda c: c["Name"]):
        cname = c["Name"]
        ctags = [t for t in (c.get("Tags") or []) if isinstance(t, str)]
        cd = class_docs.get(cname, {})
        # No creator-docs reference page → shipped in the engine but undocumented (often unreleased/in development).
        class_undoc = cname not in class_docs
        tag_list = [t.lower() for t in ctags] + (["undocumented"] if class_undoc else [])
        classes_rows.append([cname, c.get("Superclass", ""), ",".join(tag_list), cd.get("summary", "")])
        if cd.get("summary"):
            summaries.append({"k": cname, "s": cd["summary"]})
        if "Deprecated" in ctags:
            dep_rows.append([cname, "", "class", "", cd.get("dep", "")])
        for m in sorted(c["Members"], key=lambda m: m["Name"]):
            read, write = security(m)
            flags = flags_for(m)
            key = f"{cname}.{m['Name']}"
            d = docs.get(key, {})
            if d.get("superseded_hint") and "deprecated" not in flags:
                flags.append("superseded")
            scriptable = read in ("None", "PluginSecurity") and "notscriptable" not in flags and "hidden" not in flags
            if (class_undoc or key not in docs) and scriptable and "deprecated" not in flags:
                flags.append("undocumented")
            member_rows.append([cname, m["Name"], m["MemberType"], signature(m), read, write,
                                m.get("ThreadSafety", ""), ",".join(flags)])
            if d.get("summary"):
                summaries.append({"k": key, "s": d["summary"]})
            if "deprecated" in flags or "superseded" in flags:
                prefer = next((f[7:] for f in flags if f.startswith("prefer=")), "")
                dep_rows.append([cname, m["Name"], m["MemberType"], prefer, d.get("dep") or d.get("superseded_hint", "")])

    enum_rows = []
    for e in sorted(dump["Enums"], key=lambda e: e["Name"]):
        edoc = {}
        epath = REF / "enums" / f"{e['Name']}.yaml"
        if epath.exists():
            ed = load_yaml(epath)
            edoc = {i["name"]: i for i in ed.get("items") or []}
            if ed.get("summary"):
                summaries.append({"k": "Enum." + e["Name"], "s": clean(ed.get("summary"))})
        for item in e["Items"]:
            flags = [t.lower() for t in (item.get("Tags") or []) if isinstance(t, str)]
            idoc = edoc.get(item["Name"], {})
            if idoc.get("deprecation_message") and "deprecated" not in flags:
                flags.append("deprecated")
            enum_rows.append([e["Name"], item["Name"], str(item.get("Value", "")), ",".join(flags)])
            if "deprecated" in flags:
                dep_rows.append(["Enum." + e["Name"], item["Name"], "EnumItem", "", clean(idoc.get("deprecation_message"), 400)])

    # Datatypes, libraries, globals (not present in the reflection dump).
    dt_rows = []
    for folder, kind in (("datatypes", "datatype"), ("libraries", "library"), ("globals", "global")):
        for path in sorted((REF / folder).glob("*.yaml")):
            data = load_yaml(path)
            owner = data.get("name", path.stem)
            for section in ("constructors", "constants", "properties", "methods", "functions", "math_operations"):
                for m in data.get(section) or []:
                    name = m.get("name") or m.get("operation", "")
                    if section == "math_operations":
                        name = f"{m.get('type_a', '')} {m.get('operation', '')} {m.get('type_b', '')}".strip()
                    params = ", ".join(f"{p.get('name')}: {p.get('type', '')}" for p in m.get("parameters") or [])
                    rets = ", ".join(str(r.get("type", "")) for r in m.get("returns") or [])
                    sig = m.get("type") or (f"({params})" + (f" -> {rets}" if rets else ""))
                    flags = [t.lower() for t in (m.get("tags") or []) if isinstance(t, str)]
                    desc = m.get("description") or ""
                    if m.get("deprecation_message") and "deprecated" not in flags:
                        flags.append("deprecated")
                    elif re.search(r"superseded|should not be used for (new|future) work", desc, re.I):
                        flags.append("superseded")
                    kind_name = {"constructors": "constructor", "constants": "constant", "properties": "property",
                                 "methods": "method", "functions": "function", "math_operations": "operator"}[section]
                    dt_rows.append([owner, name, kind_name,
                                    str(sig), ",".join(flags)])
                    if m.get("summary"):
                        summaries.append({"k": name, "s": clean(m.get("summary"))})
                    if "deprecated" in flags or "superseded" in flags:
                        dep_rows.append([owner, name, kind, "", clean(m.get("deprecation_message") or desc, 400)])

    def write_tsv(name: str, header: list[str], rows: list[list[str]]) -> None:
        with (OUT / name).open("w", encoding="utf-8", newline="\n") as f:
            f.write("\t".join(header) + "\n")
            for r in rows:
                f.write("\t".join(str(x).replace("\t", " ").replace("\n", " ") for x in r) + "\n")

    write_tsv("classes.tsv", ["class", "superclass", "tags", "summary"], classes_rows)
    write_tsv("members.tsv", ["class", "member", "kind", "type_or_signature", "read", "write", "thread", "flags"], member_rows)
    write_tsv("enums.tsv", ["enum", "item", "value", "flags"], enum_rows)
    write_tsv("datatypes.tsv", ["owner", "member", "kind", "signature", "flags"], dt_rows)
    write_tsv("deprecated.tsv", ["owner", "member", "kind", "preferred", "message"], dep_rows)
    with (OUT / "summaries.jsonl").open("w", encoding="utf-8", newline="\n") as f:
        for s in summaries:
            f.write(json.dumps(s, ensure_ascii=False) + "\n")
    meta = {
        "generated_from": {
            "api_dump": {"repo": "MaximumADHD/Roblox-Client-Tracker", "file": "Full-API-Dump.json",
                         "client_version": version, **lock["sources"].get("api-dump", {})},
            "engine_yaml": {"repo": "Roblox/creator-docs", "path": "content/en-us/reference/engine",
                            "studio_version": studio_version, **lock["sources"].get("creator-docs", {})},
        },
        "counts": {"classes": len(classes_rows), "members": len(member_rows), "enum_items": len(enum_rows),
                   "datatype_library_global_entries": len(dt_rows), "deprecated_or_superseded": len(dep_rows)},
        "note": "Generated file. Security 'None' = callable from ordinary game scripts. PluginSecurity/"
                "RobloxScriptSecurity/LocalUserSecurity = NOT available to game scripts. 'notscriptable' = Studio "
                "property only. Priority when sources disagree: reflection dump metadata > YAML text.",
    }
    (OUT / "META.json").write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(meta["counts"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
