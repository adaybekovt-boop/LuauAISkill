#!/usr/bin/env python3
"""Validate every Luau code block inside Markdown knowledge files.

Fence conventions (see knowledge/00-START-HERE.md):
  ```luau   full typecheck with luau-lsp + Roblox API definitions (type errors and
            use of deprecated APIs fail)
  ```lua    syntax-only check with luau-compile (fragments, "bad" examples)
  other     ignored (```text, ```bash, ```json ...)

Directives inside a ```luau block (comment lines anywhere in the block):
  -- @path ReplicatedStorage/Shared/Signal        place block in a virtual Rojo tree
         (suffix .server => Script, .client => LocalScript, else ModuleScript)
         so require(ReplicatedStorage.Shared.Signal) / require(script.Parent.X)
         resolve and are typechecked ACROSS blocks and files.
  -- @run      pure Luau: also execute with the `luau` CLI; exit code must be 0
              (use assert(...) to prove semantics claimed in the text).

Toolchain: tools/setup_luau_toolchain.sh (or set LUAU_TOOLCHAIN).
Exit code 0 = PASS, 1 = FAIL, 2 = toolchain missing.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FENCE = re.compile(r"^(\s*)(```+|~~~+)\s*([\w+-]*)\s*$")
PATH_DIRECTIVE = re.compile(r"^\s*--\s*@path\s+(\S+)\s*$", re.M)
RUN_DIRECTIVE = re.compile(r"^\s*--\s*@run\b", re.M)
DIAG = re.compile(r"^(?P<file>.+?)(?: \[[^\]]*\])?\((?P<line>\d+),(?P<col>\d+)\): (?P<cat>\w+): (?P<msg>.*)$")
# Deprecated API in a ```luau (recommended) block is an error: bad examples belong in ```lua.
ERROR_CATEGORIES = {"TypeError", "SyntaxError", "DeprecatedApi", "DeprecatedGlobal"}
SERVICES = {
    "Workspace", "Players", "Lighting", "ReplicatedFirst", "ReplicatedStorage",
    "ServerScriptService", "ServerStorage", "StarterGui", "StarterPack",
    "StarterPlayer", "SoundService", "Teams", "TextChatService",
}


@dataclass
class Block:
    md: Path
    start_line: int  # 1-based line of first code line in the .md
    lang: str
    code: str
    path: str | None = None
    run: bool = False
    file: Path | None = None
    issues: list[str] = field(default_factory=list)


def show(md: Path) -> str:
    try:
        return md.relative_to(ROOT).as_posix()
    except ValueError:
        return str(md)


def toolchain() -> Path:
    return Path(os.environ.get("LUAU_TOOLCHAIN", ROOT / ".toolchain"))


def extract(md: Path) -> list[Block]:
    blocks: list[Block] = []
    lines = md.read_text(encoding="utf-8").splitlines()
    i = 0
    while i < len(lines):
        m = FENCE.match(lines[i])
        if not m:
            i += 1
            continue
        fence, lang = m.group(2), m.group(3).lower()
        body: list[str] = []
        j = i + 1
        while j < len(lines) and not lines[j].strip().startswith(fence):
            body.append(lines[j])
            j += 1
        if lang in ("luau", "lua"):
            code = "\n".join(body) + "\n"
            b = Block(md, i + 2, lang, code)
            pm = PATH_DIRECTIVE.search(code)
            b.path = pm.group(1) if pm and lang == "luau" else None
            b.run = bool(RUN_DIRECTIVE.search(code)) and lang == "luau"
            blocks.append(b)
        i = j + 1
    return blocks


def class_for(name: str) -> tuple[str, str]:
    for suffix, cls in ((".server", "Script"), (".client", "LocalScript")):
        if name.endswith(suffix):
            return name[: -len(suffix)], cls
    return name, "ModuleScript"


def build_sourcemap(blocks: list[Block], work: Path) -> dict:
    root: dict = {"name": "Game", "className": "DataModel", "children": []}

    def child(node: dict, name: str, cls: str) -> dict:
        for c in node.setdefault("children", []):
            if c["name"] == name:
                return c
        c = {"name": name, "className": cls, "children": []}
        node["children"].append(c)
        return c

    for s in sorted(SERVICES):
        child(root, s, s)
    seen: dict[str, Block] = {}
    for b in blocks:
        if not b.path:
            continue
        parts = b.path.replace(".luau", "").strip("/").split("/")
        if parts[0] not in SERVICES:
            b.issues.append(f"@path must start with a service ({', '.join(sorted(SERVICES))}): {b.path}")
            continue
        key = "/".join(parts)
        if key in seen:
            other = seen[key]
            b.issues.append(f"@path {b.path} already defined in {show(other.md)}:{other.start_line}")
            continue
        seen[key] = b
        node = child(root, parts[0], parts[0])
        for folder in parts[1:-1]:
            node = child(node, folder, "Folder")
        name, cls = class_for(parts[-1])
        leaf = child(node, name, cls)
        leaf["className"] = cls
        leaf["filePaths"] = [b.file.relative_to(work).as_posix()]
    return root


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paths", nargs="*", default=["knowledge"], help="Markdown files or directories")
    ap.add_argument("--warnings", action="store_true", help="also print lint warnings")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    tc = toolchain()
    lsp, compiler, runner = tc / "luau-lsp", tc / "luau-compile", tc / "luau"
    defs = tc / "globalTypes.d.luau"
    missing = [p.name for p in (lsp, compiler, runner, defs) if not p.exists()]
    if missing:
        print(f"Toolchain missing in {tc}: {missing}. Run tools/setup_luau_toolchain.sh", file=sys.stderr)
        return 2

    mds: list[Path] = []
    for p in args.paths:
        p = (ROOT / p) if not Path(p).is_absolute() else Path(p)
        mds.extend(sorted(p.rglob("*.md")) if p.is_dir() else [p])
    blocks = [b for md in mds for b in extract(md)]

    work = Path(tempfile.mkdtemp(prefix="luau-blocks-"))
    try:
        by_file: dict[str, Block] = {}
        for n, b in enumerate(blocks):
            if b.path:
                rel = Path("src") / (b.path.replace(".luau", "").strip("/") + ".luau")
            else:
                rel = Path("blocks") / f"{b.md.stem}__{n:04d}.luau"
            b.file = work / rel
            b.file.parent.mkdir(parents=True, exist_ok=True)
            b.file.write_text(b.code, encoding="utf-8")
            by_file[rel.as_posix()] = b
        (work / "sourcemap.json").write_text(json.dumps(build_sourcemap(blocks, work)), encoding="utf-8")

        luau_blocks = [b for b in blocks if b.lang == "luau" and not b.issues]
        warnings: list[str] = []
        if luau_blocks:
            cmd = [str(lsp), "analyze", f"--definitions={defs}", "--sourcemap=sourcemap.json",
                   "--platform=roblox"] + [b.file.relative_to(work).as_posix() for b in luau_blocks]
            out = subprocess.run(cmd, cwd=work, capture_output=True, text=True)
            for line in (out.stdout + out.stderr).splitlines():
                m = DIAG.match(line.strip())
                if not m:
                    continue
                fpath = Path(m.group("file"))
                if fpath.is_absolute():
                    try:
                        fpath = fpath.resolve().relative_to(work.resolve())
                    except ValueError:
                        continue
                rel = os.path.normpath(str(fpath)).replace(os.sep, "/")
                b = by_file.get(rel)
                if b is None:
                    continue
                where = f"{show(b.md)}:{b.start_line + int(m.group('line')) - 1}"
                text = f"{where}: {m.group('cat')}: {m.group('msg')}"
                (b.issues if m.group("cat") in ERROR_CATEGORIES else warnings).append(text)

        for b in blocks:
            if b.issues and b.lang == "luau":
                continue
            if b.lang == "lua":
                r = subprocess.run([str(compiler), "--null", str(b.file)], capture_output=True, text=True)
                if r.returncode != 0:
                    b.issues.append(f"{show(b.md)}:{b.start_line}: SyntaxError: {(r.stdout + r.stderr).strip()}")
            elif b.run:
                r = subprocess.run([str(runner), str(b.file)], capture_output=True, text=True, timeout=60)
                if r.returncode != 0:
                    b.issues.append(f"{show(b.md)}:{b.start_line}: RunError: {(r.stdout + r.stderr).strip()[-800:]}")

        errors = [i if ":" in i.split(" ")[0] else f"{show(b.md)}:{b.start_line}: {i}"
                  for b in blocks for i in b.issues]
        summary = {
            "status": "FAIL" if errors else "PASS",
            "markdown_files": len(mds),
            "luau_blocks_typechecked": sum(1 for b in blocks if b.lang == "luau"),
            "lua_blocks_syntax_checked": sum(1 for b in blocks if b.lang == "lua"),
            "blocks_executed": sum(1 for b in blocks if b.run),
            "modules_in_virtual_tree": sum(1 for b in blocks if b.path),
            "errors": len(errors),
            "warnings": len(warnings),
            "note": "Static typecheck against Roblox API definitions + CLI execution of @run blocks. Not a Roblox Studio runtime test.",
        }
        if args.json:
            print(json.dumps({**summary, "error_list": errors, "warning_list": warnings}, ensure_ascii=False, indent=2))
        else:
            for e in errors:
                print("ERROR", e)
            if args.warnings:
                for w in warnings:
                    print("warn ", w)
            print(json.dumps(summary, ensure_ascii=False, indent=2))
        return 1 if errors else 0
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
