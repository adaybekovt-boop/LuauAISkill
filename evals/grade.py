#!/usr/bin/env python3
"""Pre-grade eval answers automatically; the rubric (evals/RUBRIC.md) is applied by a human or a judge model.

Answers: a directory with one Markdown file per case, named <ID>.md (e.g. NET-01.md).
Automatic checks per answer:
  forbid       regexes that must NOT match inside the answer's Luau/Lua code blocks (code only, so prose like
               "Blacklist was removed" is not penalised)
  require_any  at least one regex must match anywhere in the answer
  api          every engine API referenced in code blocks must exist (tools/check_api_refs.py); unknown = likely
               hallucinated; deprecated usage is reported as a warning
  lang         Russian prompts should get a Cyrillic answer
Output: a table + evals/runs/<name>.json (gitignored). Auto results are a pre-screen, never the final score.

  python evals/grade.py --list                         case counts by category
  python evals/grade.py answers/ --name model-A        grade a directory of answers
  python evals/grade.py --print NET-01                 show a case (prompt + fixture) for manual runs
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CASES = ROOT / "evals" / "cases"
RUNS = ROOT / "evals" / "runs"
sys.path.insert(0, str(ROOT / "tools"))
import check_api_refs  # noqa: E402

CODE = re.compile(r"```(?:luau|lua)\s*\n(.*?)```", re.S)


def load_cases() -> list[dict]:
    out = []
    for f in sorted(CASES.glob("*.jsonl")):
        for line in f.read_text(encoding="utf-8").splitlines():
            if line.strip():
                out.append(json.loads(line))
    return out


def api_findings(code: str) -> list[tuple[str, str]]:
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "answer.luau"
        path.write_text(code, encoding="utf-8")
        restricted = check_api_refs.restricted_props()
        owners = check_api_refs.datatype_owners()
        return [(sev, msg) for _line, sev, msg in check_api_refs.check_file(path, restricted, owners)]


def grade(case: dict, answer: str) -> dict:
    code = "\n".join(CODE.findall(answer))
    auto = case.get("auto", {})
    res: dict = {"id": case["id"], "category": case["category"], "flags": []}
    for pattern in auto.get("forbid", []):
        if code and re.search(pattern, code, re.M):
            res["flags"].append(f"forbidden pattern in code: {pattern}")
    req = auto.get("require_any", [])
    if req and not any(re.search(p, answer, re.M) for p in req):
        res["flags"].append("missing required element: " + " | ".join(req))
    if code:
        for sev, msg in api_findings(code):
            res["flags"].append(f"api {sev}: {msg}")
    if case.get("lang") == "ru" and not re.search(r"[А-Яа-яЁё]", answer):
        res["flags"].append("answered in the wrong language (expected Russian)")
    res["auto"] = "FLAGGED" if res["flags"] else "PASS-AUTO"
    return res


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("answers", nargs="?")
    ap.add_argument("--name", default="run")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--print", dest="show")
    a = ap.parse_args()
    cases = load_cases()
    if a.list:
        counts: dict[str, int] = {}
        for c in cases:
            counts[c["category"]] = counts.get(c["category"], 0) + 1
        for cat, n in sorted(counts.items()):
            print(f"{cat:15} {n}")
        print(f"{'total':15} {len(cases)}")
        return 0
    if a.show:
        case = next((c for c in cases if c["id"] == a.show), None)
        if not case:
            print("unknown case id")
            return 1
        print(case["prompt"])
        if case.get("fixture"):
            print("\n```luau\n" + (ROOT / case["fixture"]).read_text(encoding="utf-8").rstrip() + "\n```")
        return 0
    if not a.answers:
        ap.print_help()
        return 1
    folder = Path(a.answers)
    results = []
    for case in cases:
        f = folder / f"{case['id']}.md"
        if not f.exists():
            continue
        results.append(grade(case, f.read_text(encoding="utf-8")))
    if not results:
        print("no answers found (expected files like NET-01.md)")
        return 1
    for r in results:
        print(f"{r['id']:8} {r['auto']:10} " + ("; ".join(r["flags"])[:160]))
    flagged = sum(1 for r in results if r["flags"])
    print(f"\n{len(results)} answers, {flagged} flagged by automatic checks (apply RUBRIC.md for the real score)")
    RUNS.mkdir(parents=True, exist_ok=True)
    (RUNS / f"{a.name}.json").write_text(json.dumps(results, indent=1, ensure_ascii=False), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
