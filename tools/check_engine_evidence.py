#!/usr/bin/env python3
"""Validate actual engine smoke receipts; fail closed until every required case ran.

  python tools/check_engine_evidence.py                  release gate (pending is failure)
  python tools/check_engine_evidence.py --allow-pending  infrastructure/schema validation only
  python tools/check_engine_evidence.py --digest inventory
  python tools/check_engine_evidence.py --extract path/to/server-console.txt

This checks evidence consistency/integrity, not its authenticity. It cannot execute Roblox,
prove the provenance of a hand-edited capture, or promote a CLI/typecheck run to engine evidence.
No generated qa files are written. Raw captures must be retained for maintainer review.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "maintainers" / "engine-smoke" / "manifest.json"
MARKER = "LUAU_RELEASE_SMOKE_RESULT "
PRESETS = ("HorrorInterior", "BackroomsOffice", "DarkCorridor", "NightExterior", "Sunset", "FogDay",
           "IndustrialWarehouse", "Poolrooms", "EmergencyRed")
# Fixed release scope. A manifest cannot silently weaken assertions, client counts, or engine requirements.
REQUIRED = {
    "save-system": ("data", 0, ("acquire-real-key", "foreign-lock-rejected", "uncached-save-readback",
                                  "release-clears-lock", "second-owner-preserves-data", "disposable-key-cleaned")),
    "network-rate-limiter": ("net", 2, ("invalid-payload-rejected", "valid-request-roundtrip",
                                          "rate-limit-enforced", "per-player-budget-isolated", "server-counters-match")),
    "inventory": ("interaction", 2, ("invalid-slot-no-mutation", "move-server-authoritative",
                                        "use-consumes-and-heals", "owner-receives-snapshot", "other-inventory-unchanged")),
    "interaction": ("interaction", 1, ("tag-creates-prompt", "near-prompt-dispatched",
                                          "disabled-target-unchanged", "distant-attempt-unchanged", "untag-destroys-prompt")),
    "hitscan-gun": ("combat", 1, ("spoofed-origin-rejected", "server-raycast-damages",
                                    "server-ammo-decrements", "wall-blocks-damage", "reload-restores-magazine")),
    "round-manager": ("rounds", 2, ("two-players-start-round", "map-created", "phase-and-deadline-replicate",
                                       "elimination-selects-winner", "map-cleaned-after-results", "next-cycle-respawns")),
    "sprint-crouch-stamina": ("movement", 1, ("input-actions-created", "crouch-speed-applied",
        "stand-speed-restored", "sprint-speed-applied", "server-stamina-drains", "server-stamina-recovers",
        "respawn-clears-movement")),
    "npc-patrol": ("npc", 1, ("tag-binds-patrol", "path-and-physics-move-npc", "server-owns-npc",
                                 "untag-stops-manager-writes")),
    "settings-menu": ("settings", 1, ("menu-and-controls-created", "client-sanitizes-settings",
                                         "camera-fov-applies", "server-save-sync-roundtrip", "menu-survives-respawn")),
    "lighting-presets": ("lighting", 1, tuple("preset-" + name for name in PRESETS) + ("effects-not-duplicated",)),
}
HEX = re.compile(r"^[0-9a-f]{64}$")
UUID = re.compile(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")


class EvidenceError(ValueError):
    """Invalid evidence is a normal check failure, not a Python traceback."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise EvidenceError(message)


def unique_json(text: str) -> Any:
    def pairs(items: list[tuple[str, Any]]) -> dict:
        result = {}
        for key, value in items:
            require(key not in result, f"duplicate JSON key: {key}")
            result[key] = value
        return result
    try:
        return json.loads(text, object_pairs_hook=pairs,
                          parse_constant=lambda token: (_ for _ in ()).throw(EvidenceError(f"non-finite JSON: {token}")))
    except json.JSONDecodeError as exc:
        raise EvidenceError(f"invalid JSON: {exc}") from exc


def read_json(path: Path) -> Any:
    try:
        return unique_json(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError) as exc:
        raise EvidenceError(f"cannot read {path}: {exc}") from exc


def within(base: Path, value: Any, *, directory: bool = False) -> Path:
    require(isinstance(value, str) and bool(value), "path must be a nonempty relative string")
    relative = Path(value)
    require(not relative.is_absolute() and ".." not in relative.parts and "\\" not in value,
            f"unsafe artifact/source path: {value}")
    path = (base / relative).resolve()
    require(path.is_relative_to(base.resolve()), f"path escapes root: {value}")
    require(path.is_dir() if directory else path.is_file(), f"missing {'directory' if directory else 'file'}: {value}")
    return path


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def expected_roots(case_id: str) -> list[str]:
    return [f"examples/{REQUIRED[case_id][0]}", "examples/lib", "examples/release-smoke/ServerScriptService",
            "examples/release-smoke/StarterPlayer"]


def source_digest(case: dict, root: Path = ROOT) -> str:
    paths: set[Path] = {within(root, case["project"]), within(root, "sources/lock.json")}
    for relative in case["source_roots"]:
        directory = within(root, relative, directory=True)
        sources = list(directory.rglob("*.luau"))
        require(bool(sources), f"source root contains no Luau: {relative}")
        for source in sources:
            require(source.resolve().is_relative_to(root.resolve()), f"source symlink escapes repository: {source}")
            paths.add(source.resolve())
    digest = hashlib.sha256()
    for path in sorted(paths, key=lambda item: item.relative_to(root.resolve()).as_posix()):
        relative = path.relative_to(root.resolve()).as_posix().encode("utf-8")
        content = path.read_bytes()
        digest.update(len(relative).to_bytes(8, "big") + relative)
        digest.update(len(content).to_bytes(8, "big") + content)
    return digest.hexdigest()


def captured_results(text: str) -> list[dict]:
    results = []
    for line in text.splitlines():
        if MARKER not in line:
            continue
        # Studio timestamps/prefixes before the marker are allowed. Nothing after the JSON is ignored.
        result = unique_json(line.split(MARKER, 1)[1].strip())
        require(isinstance(result, dict), "captured result must be an object")
        results.append(result)
    require(bool(results), "capture has no machine-readable engine result marker")
    return results


def timestamp(value: Any, field: str) -> dt.datetime:
    require(isinstance(value, str), f"{field} must be an ISO timestamp")
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise EvidenceError(f"invalid {field}") from exc
    require(parsed.tzinfo is not None, f"{field} must include a timezone")
    return parsed


def verify_file(spec: Any, base: Path, label: str) -> Path:
    require(isinstance(spec, dict), f"{label} must contain path and sha256")
    path = within(base, spec.get("path"))
    expected = spec.get("sha256")
    require(isinstance(expected, str) and bool(HEX.fullmatch(expected)), f"{label}: invalid sha256")
    require(path.stat().st_size > 0, f"{label}: empty artifact")
    require(sha256(path) == expected, f"{label}: sha256 mismatch")
    return path


def validate_result(result: Any, case: dict, digest: str) -> None:
    require(isinstance(result, dict), "result must be an object")
    case_id = case["id"]
    require(type(result.get("schema_version")) is int and result["schema_version"] == 1, "unsupported result schema_version")
    require(result.get("case") == case_id, "result case does not match manifest")
    require(isinstance(result.get("run_id"), str) and bool(UUID.fullmatch(result["run_id"])), "missing/invalid run_id")
    require(result.get("source_digest") == digest, "stale/mismatched source digest; rerun the engine smoke")
    require(result.get("status") == "PASS" and not result.get("error"), "engine result is failed or has an error")
    require(result.get("environment") in case["allowed_environments"], "unsupported environment for this case")
    clients = result.get("client_count")
    require(type(clients) is int and clients >= case["minimum_clients"], "insufficient real clients")
    if result["environment"] == "open-cloud":
        require(clients == 0, "Open Cloud cannot supply client evidence")
    for field in ("universe_id", "place_id", "place_version"):
        value = result.get(field)
        require(type(value) is int and value >= 0, f"invalid {field}")
        if result["environment"] == "open-cloud" or case_id == "save-system":
            require(value > 0, f"{field} must identify a published isolated test place")
    version = result.get("engine_version")
    require(isinstance(version, str) and bool(re.fullmatch(r"[0-9]+(?:\.[0-9]+){2,}", version)),
            "engine_version must be the actual dotted Roblox version from the run")
    start = timestamp(result.get("started_at"), "started_at")
    end = timestamp(result.get("finished_at"), "finished_at")
    require(start <= end <= dt.datetime.now(dt.timezone.utc) + dt.timedelta(minutes=5), "invalid/future execution time")
    require((end - start).total_seconds() <= 1250, "execution duration exceeds harness deadline")
    assertions = result.get("assertions")
    require(isinstance(assertions, list) and bool(assertions), "missing executed assertions")
    ids = []
    for assertion in assertions:
        require(isinstance(assertion, dict), "assertion must be an object")
        require(assertion.get("status") == "PASS", "receipt contains failed/skipped assertion")
        require(isinstance(assertion.get("id"), str), "assertion ID must be a string")
        require(isinstance(assertion.get("detail"), str), "assertion detail must be a string")
        ids.append(assertion["id"])
    require(len(ids) == len(set(ids)), "duplicate assertion IDs")
    require(set(ids) == set(case["assertions"]), "executed assertion set does not match required smoke coverage")


def validate_receipt(receipt: Any, case: dict, base: Path, digest: str) -> str:
    require(isinstance(receipt, dict), "receipt must be an object")
    require(type(receipt.get("schema_version")) is int and receipt["schema_version"] == 1, "unsupported receipt schema_version")
    result_path = verify_file(receipt.get("result"), base, "result")
    capture_path = verify_file(receipt.get("capture"), base, "capture")
    require(result_path != capture_path, "retain raw capture separately from extracted result")
    result = read_json(result_path)
    validate_result(result, case, digest)
    try:
        captured = captured_results(capture_path.read_text(encoding="utf-8"))
    except UnicodeError as exc:
        raise EvidenceError("capture must be UTF-8 console/log text") from exc
    matching = [item for item in captured if item.get("run_id") == result["run_id"]]
    require(len(matching) == 1 and matching[0] == result, "raw capture does not contain exactly this result")
    # A later failure in the same capture cannot be hidden by selecting an older PASS.
    require(captured[-1] == result, "result is not the final run in its capture")
    runner = receipt.get("runner")
    require(isinstance(runner, dict), "missing runner provenance")
    require(runner.get("environment") == result["environment"], "runner environment mismatch")
    require(isinstance(runner.get("id"), str) and bool(runner["id"].strip()), "missing Studio session/task ID")
    require(runner.get("engine_version") == result["engine_version"], "runner engine version mismatch")
    if result["environment"] == "studio-server-clients":
        require(runner.get("mode") in ("Server & Clients", "Run"), "Studio mode must be explicit")
        require(runner.get("mode") != "Run" or case["minimum_clients"] == 0, "Run mode has no clients")
        require(runner.get("clients") == result["client_count"], "runner client count mismatch")
        require(receipt.get("label") == "STUDIO TESTED", "Studio receipts require STUDIO TESTED label")
    else:
        require(receipt.get("label") == "CLOUD EXECUTED", "Cloud receipts require CLOUD EXECUTED label")
        task = read_json(verify_file(receipt.get("task"), base, "Open Cloud task"))
        require(isinstance(task, dict), "Open Cloud task must be an object")
        require(task.get("state") == "COMPLETE", "Open Cloud task did not complete successfully")
        require(not task.get("error"), "Open Cloud task contains an error")
        require(task.get("path") == runner["id"], "Open Cloud task identity mismatch")
        require(isinstance(task.get("output"), dict), "Open Cloud task output is missing or invalid")
        require(task["output"].get("results") == [result], "Open Cloud output does not match the captured smoke result")
        # The official task resource path binds universe/place; published version is recorded separately.
        prefix = f'universes/{result["universe_id"]}/places/{result["place_id"]}/'
        require(runner["id"].startswith(prefix), "Open Cloud task path has the wrong universe/place")
        suffix = runner["id"][len(prefix):]
        match = re.fullmatch(r"(?:versions/([1-9][0-9]*)/)?(?:luau-execution-session-tasks/[0-9a-fA-F-]{36}|"
                             r"luau-execution-sessions/[0-9a-fA-F-]{36}/tasks/[0-9a-fA-F-]{36})", suffix)
        require(match is not None, "invalid Open Cloud task resource path")
        if match and match.group(1):
            require(int(match.group(1)) == result["place_version"], "task path place version mismatch")
        require(runner.get("place_version") == result["place_version"], "Open Cloud published version mismatch")
    screenshots = receipt.get("screenshots", {})
    require(isinstance(screenshots, dict), "screenshots must be keyed by preset")
    require(set(screenshots) == set(case["screenshots"]), "missing/extra per-preset visual captures")
    image_hashes: set[str] = set()
    for name, spec in screenshots.items():
        path = verify_file(spec, base, f"screenshot {name}")
        require(spec.get("run_id") == result["run_id"], f"screenshot {name}: run ID mismatch")
        captured_at = timestamp(spec.get("captured_at"), f"screenshot {name} captured_at")
        require(timestamp(result["started_at"], "started_at") <= captured_at <= timestamp(result["finished_at"], "finished_at"),
                f"screenshot {name}: capture is outside this run")
        require(spec["sha256"] not in image_hashes, "one image cannot stand in for multiple preset captures")
        image_hashes.add(spec["sha256"])
        content = path.read_bytes()
        require(len(content) > 100, f"screenshot {name} is truncated")
        require(content.startswith(b"\x89PNG\r\n\x1a\n") or content.startswith(b"\xff\xd8\xff"),
                f"screenshot {name} is not PNG/JPEG data")
    return result["run_id"]


def validate_manifest(manifest: Any, root: Path = ROOT, evidence_base: Path | None = None,
                      allow_pending: bool = False) -> tuple[list[str], list[str]]:
    base = evidence_base or MANIFEST.parent
    errors: list[str] = []
    pending: list[str] = []
    try:
        require(isinstance(manifest, dict), "manifest must be an object")
        require(type(manifest.get("schema_version")) is int and manifest["schema_version"] == 1, "unsupported manifest schema_version")
        cases = manifest.get("cases")
        require(isinstance(cases, list), "manifest cases must be a list")
        require(all(isinstance(case, dict) and isinstance(case.get("id"), str) for case in cases), "invalid case")
        ids = [case["id"] for case in cases]
        require(len(ids) == len(set(ids)), "duplicate case IDs")
        require(set(ids) == set(REQUIRED), "manifest must contain exactly the ten required release cases")
    except EvidenceError as exc:
        return [str(exc)], []
    run_ids: set[str] = set()
    for case in cases:
        case_id = case["id"]
        try:
            family, clients, assertions = REQUIRED[case_id]
            require(case.get("project") == f"examples/release-smoke/projects/{case_id}.project.json", "wrong fixture project")
            project = read_json(within(root, case["project"]))
            require(isinstance(project, dict) and isinstance(project.get("tree"), dict), "invalid fixture project")
            workspace = project["tree"].get("Workspace")
            require(isinstance(workspace, dict) and isinstance(workspace.get("$attributes"), dict), "missing fixture attributes")
            require(workspace["$attributes"].get("ReleaseSmokeCase") == case_id,
                    "fixture case attribute mismatch")
            within(root, case.get("recipe"))
            require(case.get("source_roots") == expected_roots(case_id), "source roots cannot weaken coverage")
            require(case.get("minimum_clients") == clients and type(case["minimum_clients"]) is int, "client requirement changed")
            expected_envs = ["studio-server-clients"] + (["open-cloud"] if case_id == "save-system" else [])
            require(case.get("allowed_environments") == expected_envs, "engine requirement changed")
            require(case.get("assertions") == list(assertions), "required assertions changed")
            require(case.get("screenshots") == (list(PRESETS) if case_id == "lighting-presets" else []), "visual requirement changed")
            digest = source_digest(case, root)
            receipts = case.get("receipts")
            require(isinstance(receipts, list), "receipts must be a list")
            if case.get("status") == "NOT RUN":
                require(not receipts, "NOT RUN cannot contain receipts; review and state the actual evidence label")
                require(isinstance(case.get("blocker"), str) and bool(case["blocker"].strip()), "pending case must state its blocker")
                pending.append(case_id)
                if not allow_pending:
                    errors.append(f"{case_id}: NOT RUN — {case['blocker']}")
                continue
            require(case.get("status") in ("STUDIO TESTED", "CLOUD EXECUTED"), "invalid evidence status")
            require(bool(receipts), "executed claim has no engine receipt")
            require(not case.get("blocker"), "executed case must clear its pending blocker")
            for spec in receipts:
                receipt = read_json(verify_file(spec, base, "receipt"))
                require(receipt.get("label") == case["status"], "case label differs from receipt")
                run_id = validate_receipt(receipt, case, base, digest)
                require(run_id not in run_ids, "run ID reused by another receipt")
                run_ids.add(run_id)
        except (EvidenceError, OSError, TypeError, KeyError) as exc:
            errors.append(f"{case_id}: {exc}")
    return errors, pending


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--manifest", type=Path, default=MANIFEST)
    parser.add_argument("--allow-pending", action="store_true", help="schema-only infrastructure check; never release approval")
    parser.add_argument("--require-executed", action="store_true", help="explicit default fail-closed release behavior")
    parser.add_argument("--digest", choices=tuple(REQUIRED), help="print the source digest to set before an engine run")
    parser.add_argument("--extract", type=Path, help="print the last captured result without editing evidence status")
    args = parser.parse_args(argv)
    try:
        require(not (args.allow_pending and args.require_executed), "choose schema check or executed release gate")
        if args.extract:
            print(json.dumps(captured_results(args.extract.read_text(encoding="utf-8"))[-1], indent=2))
            return 0
        manifest = read_json(args.manifest)
        if args.digest:
            cases = [case for case in manifest.get("cases", []) if case.get("id") == args.digest]
            require(len(cases) == 1, "digest case must appear exactly once")
            print(source_digest(cases[0]))
            return 0
        errors, pending = validate_manifest(manifest, evidence_base=args.manifest.resolve().parent,
                                            allow_pending=args.allow_pending)
    except (EvidenceError, OSError, UnicodeError) as exc:
        print(f"FAIL engine evidence: {exc}", file=sys.stderr)
        return 1
    for error in errors:
        print("FAIL " + error)
    if errors:
        print(f"Engine release gate BLOCKED: {len(errors)} failure(s), {len(pending)} NOT RUN")
        return 1
    if pending:
        print(f"PASS engine smoke infrastructure; {len(pending)}/{len(REQUIRED)} NOT RUN; release gate remains BLOCKED")
    else:
        print(f"PASS engine release evidence: {len(REQUIRED)}/{len(REQUIRED)} executed cases with validated artifacts")
    return 0


if __name__ == "__main__":
    sys.exit(main())
