#!/usr/bin/env python3
"""Typecheck / execute every Luau artifact in the skill. Writes qa/code-checks.json.

1. Markdown ```luau / ```lua blocks (handbook, recipes, references, tracks, SKILL.md):
   each block is typechecked standalone with luau-lsp + Roblox definitions (security level None = game scripts).
   Opt-out marker on the first non-empty line of a block (use sparingly, the reason must be honest):
     -- BAD / -- LEGACY / -- FAKE   intentionally wrong or outdated code (anti-pattern demos)
     -- fragment                    excerpt that references names defined elsewhere
2. examples/<project>/ trees (Rojo-style folders named after services): a sourcemap is generated so cross-module
   requires resolve, then every .luau file is typechecked with luau-lsp.
3. examples/tests/*.spec.luau: executed with the standalone `luau` CLI (pure modules only).

Status vocabulary (see SKILL.md): TYPECHECKED = luau-lsp strict pass with Roblox defs; CLI-EXECUTED = ran under
the Luau CLI; SKIPPED = explicit marker; FAILED = errors. Nothing here is STUDIO-TESTED.

  python tools/install_toolchain.py && python tools/fetch_sources.py --only luau-lsp
  python tools/check_code.py [--md-only | --examples-only] [paths...]
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / ".cache" / "bin"
DEFS = ROOT / ".cache" / "sources" / "luau-lsp" / "scripts" / "globalTypes.None.d.luau"
QA = ROOT / "qa" / "code-checks.json"
SKIP_DIRS = {".cache", ".git", "api", "node_modules", "maintainers"}
MARKER = re.compile(r"^\s*--\s*(BAD|LEGACY|FAKE|fragment)\b", re.I)
NS_MARKER = re.compile(r"^\s*--\s*NS\b")  # new-type-solver-only syntax (read/write props, keyof, setmetatable<>)
# Lint categories that are style-only for documentation snippets.
IGNORED = ("LocalUnused", "FunctionUnused", "ImportUnused", "LocalShadow", "SameLineStatement",
           "PlaceholderRead", "MultiLineStatement")
SERVICES = {"ReplicatedStorage", "ServerScriptService", "ServerStorage", "ReplicatedFirst", "StarterPlayer",
            "StarterGui", "StarterPack", "Workspace", "Lighting", "SoundService", "Teams"}


def tool(name: str) -> str:
    exe = BIN / (name + (".exe" if sys.platform == "win32" else ""))
    if exe.exists():
        return str(exe)
    found = shutil.which(name)
    if not found:
        sys.exit(f"missing {name}: run python tools/install_toolchain.py")
    return found


def lsp_analyze(files: list[Path], cwd: Path, sourcemap: Path | None = None, new_solver: bool = False) -> list[str]:
    if not DEFS.exists():
        sys.exit("missing Roblox definitions: run python tools/fetch_sources.py --only luau-lsp")
    cmd = [tool("luau-lsp"), "analyze", "--platform", "roblox", f"--definitions=@roblox={DEFS}",
           "--formatter", "plain"]
    if new_solver:
        cmd += ["--flag:LuauSolverV2=true"]
    if sourcemap:
        cmd += ["--sourcemap", str(sourcemap)]
    cmd += [str(f) for f in files]
    res = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    lines = [ln for ln in (res.stdout + res.stderr).splitlines()
             if ln.strip() and not ln.startswith(("[INFO]", "[WARN]"))]
    return [ln for ln in lines if not any(f": {cat}" in ln or f"{cat}:" in ln for cat in IGNORED)]


def md_blocks(path: Path) -> list[tuple[int, str, str]]:
    out, lines = [], path.read_text(encoding="utf-8").splitlines()
    i = 0
    while i < len(lines):
        m = re.match(r"^(\s*)```(luau|lua)\s*$", lines[i])
        if m:
            start = i + 1
            j = start
            while j < len(lines) and not lines[j].strip().startswith("```"):
                j += 1
            indent = len(m.group(1))
            body = "\n".join(ln[indent:] if len(ln) >= indent else ln for ln in lines[start:j])
            out.append((start + 1, m.group(2), body))
            i = j
        i += 1
    return out


def check_markdown(paths: list[Path]) -> list[dict]:
    results = []
    with tempfile.TemporaryDirectory() as tmp:
        tmpdir = Path(tmp)
        jobs = []
        for path in paths:
            for line, _lang, body in md_blocks(path):
                first = next((ln for ln in body.splitlines() if ln.strip()), "")
                rel = path.relative_to(ROOT).as_posix()
                if MARKER.match(first):
                    results.append({"file": rel, "line": line, "status": "SKIPPED",
                                    "reason": MARKER.match(first).group(1)})
                    continue
                name = f"b{len(jobs):04d}.luau"
                src = body if body.lstrip().startswith("--!") else "--!strict\n" + body
                offset = 0 if body.lstrip().startswith("--!") else 1
                (tmpdir / name).write_text(src + "\n", encoding="utf-8")
                ns_only = bool(NS_MARKER.match(first)) or any(NS_MARKER.match(x) for x in body.splitlines()[:3])
                jobs.append((name, rel, line, offset, ns_only))
        errors: dict[str, list[str]] = {}
        # Every block must pass the new solver; blocks not marked "-- NS" must also pass the old solver
        # (Studio's default solver can differ from the CLI's).
        for solver_new in (False, True):
            eligible = [j for j in jobs if solver_new or not j[4]]
            for k in range(0, len(eligible), 150):
                chunk = eligible[k:k + 150]
                for ln in lsp_analyze([tmpdir / j[0] for j in chunk], tmpdir, new_solver=solver_new):
                    m = re.match(r"^(?:.*[\\/])?(b\d{4}\.luau)", ln)
                    if m:
                        tag = "[new solver] " if solver_new else "[old solver] "
                        errors.setdefault(m.group(1), []).append(tag + ln)
        for name, rel, line, offset, _ns in jobs:
            errs = errors.get(name, [])
            fixed = []
            for e in errs:
                mm = re.search(r"\((\d+),(\d+)\)", e)
                if mm:
                    real = line + int(mm.group(1)) - 1 - offset
                    tag = e[:13]
                    e = f"{tag}{rel}:{real}: " + e[13:].split(":", 1)[-1].strip()
                fixed.append(e)
            results.append({"file": rel, "line": line, "status": "FAILED" if errs else "TYPECHECKED",
                            "errors": fixed})
    return results


def build_sourcemap(project: Path, lib: Path | None) -> dict:
    """Map <project>/<Service>/... folders to a DataModel sourcemap understood by luau-lsp."""
    def node_for(path: Path, base: Path) -> dict | None:
        if path.is_dir():
            children = [c for c in (node_for(p, base) for p in sorted(path.iterdir())) if c]
            init = next((p for p in path.iterdir() if p.name in ("init.luau", "init.server.luau", "init.client.luau")), None)
            node = {"name": path.name, "className": "Folder", "children": children}
            if init:
                node["className"] = "Script" if ".server" in init.name else "LocalScript" if ".client" in init.name else "ModuleScript"
                node["filePaths"] = [init.relative_to(base).as_posix()]
            return node
        if path.suffix != ".luau" or path.name.startswith("init."):
            return None
        stem = path.name[:-5]
        cls = "ModuleScript"
        if stem.endswith(".server"):
            cls, stem = "Script", stem[:-7]
        elif stem.endswith(".client"):
            cls, stem = "LocalScript", stem[:-7]
        return {"name": stem, "className": cls, "filePaths": [path.relative_to(base).as_posix()]}

    services: dict[str, dict] = {}
    for root in [r for r in (project, lib) if r]:
        for svc in sorted(p for p in root.iterdir() if p.is_dir()):
            if svc.name not in SERVICES:
                continue
            node = node_for(svc, project)
            if node is None:
                continue
            node["className"] = svc.name
            if svc.name in services:
                services[svc.name]["children"].extend(node["children"])
            else:
                services[svc.name] = node
    return {"name": "Game", "className": "DataModel", "children": list(services.values())}


def check_examples(projects: list[Path]) -> list[dict]:
    results = []
    lib = ROOT / "examples" / "lib"
    for project in projects:
        files = sorted(p for p in project.rglob("*.luau") if "tests" not in p.parts)
        if not files:
            continue
        # Link the shared lib into the project so relative sourcemap paths stay inside the project root.
        linked = []
        if lib.exists() and project != lib:
            for svc in lib.iterdir():
                for f in svc.rglob("*.luau"):
                    target = project / f.relative_to(lib)
                    if not target.exists():
                        target.parent.mkdir(parents=True, exist_ok=True)
                        shutil.copyfile(f, target)
                        linked.append(target)
        try:
            smap = build_sourcemap(project, None)
            smap_path = project / "sourcemap.json"
            smap_path.write_text(json.dumps(smap, indent=1), encoding="utf-8")
            all_files = sorted(p for p in project.rglob("*.luau") if "tests" not in p.parts)
            errs = lsp_analyze(all_files, project, smap_path) + \
                lsp_analyze(all_files, project, smap_path, new_solver=True)
            by_file: dict[str, list[str]] = {}
            for e in errs:
                key = e.split("(")[0].strip()
                by_file.setdefault(Path(key).name, []).append(e)
            for f in files:
                rel = f.relative_to(ROOT).as_posix()
                fe = [e for e in errs if f.name in e.split("(")[0] or str(f) in e]
                results.append({"file": rel, "status": "FAILED" if fe else "TYPECHECKED", "errors": fe})
        finally:
            for t in linked:
                t.unlink()
                parent = t.parent
                while parent != project and not any(parent.iterdir()):
                    parent.rmdir()
                    parent = parent.parent
            (project / "sourcemap.json").unlink(missing_ok=True)
    return results


def run_cli_tests() -> list[dict]:
    results = []
    tests = sorted((ROOT / "examples" / "tests").glob("*.spec.luau"))
    for t in tests:
        res = subprocess.run([tool("luau"), str(t.relative_to(ROOT))], cwd=ROOT, capture_output=True, text=True)
        out = (res.stdout + res.stderr).strip().splitlines()
        results.append({"file": t.relative_to(ROOT).as_posix(),
                        "status": "CLI-EXECUTED" if res.returncode == 0 else "FAILED",
                        "exit": res.returncode, "tail": out[-8:]})
    return results


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paths", nargs="*")
    ap.add_argument("--md-only", action="store_true")
    ap.add_argument("--examples-only", action="store_true")
    ap.add_argument("--no-write", action="store_true", help="do not update qa/code-checks.json")
    a = ap.parse_args()
    md_paths = [Path(p).resolve() for p in a.paths if p.endswith(".md")]
    if not a.paths:
        md_paths = sorted(p for p in ROOT.rglob("*.md")
                          if not (set(p.relative_to(ROOT).parts) & SKIP_DIRS))
    report: dict = {"markdown": [], "examples": [], "cli_tests": []}
    if not a.examples_only and md_paths:
        report["markdown"] = check_markdown(md_paths)
    if not a.md_only and not [p for p in a.paths if p.endswith(".md")]:
        ex = ROOT / "examples"
        projects = [p for p in sorted(ex.iterdir()) if p.is_dir() and p.name not in ("tests", "lib")] if ex.exists() else []
        if ex.exists() and (ex / "lib").exists():
            projects.insert(0, ex / "lib")
        report["examples"] = check_examples(projects)
        report["cli_tests"] = run_cli_tests() if (ex / "tests").exists() else []
    failed = 0
    for section in ("markdown", "examples", "cli_tests"):
        for r in report[section]:
            if r["status"] == "FAILED":
                failed += 1
                where = f"{r['file']}:{r.get('line', '')}"
                print(f"FAILED {where}")
                for e in r.get("errors", r.get("tail", []))[:12]:
                    print("   " + e)
    summary = {s: {} for s in report}
    for s, rs in report.items():
        for r in rs:
            summary[s][r["status"]] = summary[s].get(r["status"], 0) + 1
    print(json.dumps(summary))
    if not a.no_write and not a.paths:
        QA.parent.mkdir(exist_ok=True)
        QA.write_text(json.dumps({"summary": summary, **report}, indent=1) + "\n", encoding="utf-8")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
