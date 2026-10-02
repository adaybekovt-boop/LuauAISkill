#!/usr/bin/env python3
"""Strict old/new-solver checks for explicitly non-game recipe entry points.

The .lua.txt launcher is copyable executable Luau for a Studio plugin/command bar.
It is intentionally excluded from the game-script None definitions project scan.
This gate copies its exact bytes to a temporary .luau file and checks PluginSecurity.
This is TYPECHECKED evidence only. It never launches Studio or labels engine execution.
"""
from __future__ import annotations
import subprocess
import sys
import tempfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
EXECUTABLE = ROOT / ".cache/bin" / ("luau-lsp.exe" if sys.platform == "win32" else "luau-lsp")
CONTEXTS = {"examples/regression/PluginLauncher.lua.txt": "PluginSecurity"}

def analyze(source: str, security: str, new_solver: bool) -> tuple[int, str]:
    if security not in {"None", "PluginSecurity"}:
        raise ValueError("unsupported recipe execution context")
    executable = EXECUTABLE
    definitions = ROOT / f".cache/sources/luau-lsp/scripts/globalTypes.{security}.d.luau"
    if not executable.exists() or not definitions.exists():
        raise FileNotFoundError("pinned luau-lsp toolchain and security definitions are required")
    with tempfile.TemporaryDirectory(prefix="recipe-context-") as directory:
        target = Path(directory) / "Launcher.luau"
        target.write_text(source, encoding="utf-8")
        command = [str(executable), "analyze", "--platform", "roblox",
                   f"--definitions=@roblox={definitions}", "--formatter", "plain"]
        if new_solver:
            command.append("--flag:LuauSolverV2=true")
        result = subprocess.run(command + [str(target)], capture_output=True, text=True,
                                cwd=directory, timeout=60)
        output = result.stdout + result.stderr
        # Pinned luau-lsp can exit zero with TypeErrors: diagnostics, not exit code, are the gate.
        ignored = ("LocalUnused:", "FunctionUnused:", "ImportUnused:", "LocalShadow:",
                   "SameLineStatement:", "PlaceholderRead:", "MultiLineStatement:")
        diagnostics = [line for line in output.splitlines() if line.strip()
                       and not line.startswith(("[INFO]", "[WARN]"))
                       and not any(label in line for label in ignored)]
        return int(result.returncode != 0 or bool(diagnostics)), output

def check_runtime_context() -> bool:
    # None definitions can omit members/services. Verify security in the pinned API index,
    # then check signatures for this Studio-only fixture with the complete plugin definitions.
    sys.path.insert(0, str(ROOT / "tools"))
    import api
    import check_code
    runtime_members = ("GetTestArgs", "AddPlayers", "EndTest", "CanLeaveTest", "LeaveTest")
    for member in runtime_members:
        found = api.resolve_member("StudioTestService", member)
        if not found or found[1]["read"] != "None":
            print(f"FAIL runtime StudioTestService.{member}: game security None required")
            return False
    previous = check_code.DEFS
    check_code.DEFS = ROOT / ".cache/sources/luau-lsp/scripts/globalTypes.PluginSecurity.d.luau"
    try:
        results = check_code.check_examples([ROOT / "examples/regression"])
    finally:
        check_code.DEFS = previous
    for result in results:
        if result["status"] == "FAILED":
            print("FAIL context signatures", result["file"], *result["errors"], sep="\n")
    ok = all(result["status"] == "TYPECHECKED" for result in results)
    if ok:
        print("TYPECHECKED regression fixture signatures: PluginSecurity old + new; runtime API security None verified")
    return ok

def main() -> int:
    failed = False
    for path, security in CONTEXTS.items():
        source = (ROOT / path).read_text(encoding="utf-8")
        if not source.startswith("--!strict"):
            raise ValueError(f"{path}: strict mode required")
        for solver in (False, True):
            code, output = analyze(source, security, solver)
            label = "new" if solver else "old"
            if code:
                failed = True
                print(f"FAIL {path}: {security} / {label} solver\n{output}")
            else:
                print(f"TYPECHECKED {path}: {security} / {label} solver")
    failed = not check_runtime_context() or failed
    print("Studio execution: NOT RUN (static gate only)")
    return int(failed)

if __name__ == "__main__":
    raise SystemExit(main())
