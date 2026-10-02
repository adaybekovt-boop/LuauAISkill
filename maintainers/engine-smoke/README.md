# Engine release smoke: runbook and evidence contract

## Current state and release gate

**All ten cases are NOT RUN in Roblox.** No connected Studio execution surface or authorized Open Cloud task was
available while this harness was built. The Python validator tests use synthetic temporary files only; they are
not evidence for any engine case. The Luau files can be typechecked with the pinned repository toolchain, but a
typecheck cannot establish runtime permissions, replication, physics, input, DataStore behavior, or visual quality.
Rojo build/import also needs to be checked on the runner; no Rojo binary was present in the build environment.

```sh
python tools/check_engine_evidence.py --allow-pending  # infrastructure only; pending is printed
python tools/check_engine_evidence.py                  # fail-closed engine release gate
python tools/check_engine_evidence.py --require-executed # same explicit release behavior
```

`check_all.py` may use the first form. A green aggregate infrastructure check does **not** release the engine gate.
The fixed case set, required assertion IDs, client counts and environment restrictions live in the validator as
well as [manifest.json](manifest.json); deleting requirements from the manifest cannot turn the gate green.

## Safe setup: separate disposable places

1. Use an empty **test** place in a dedicated test universe. Never import into a production game or connect a
   recipe fixture to production data. Save any current work first. The test creates/deletes only its own fixtures;
   inventory/weapon/round cases intentionally mutate test avatars. Stop the session to discard all runtime changes.
2. Use a current compatible Rojo installation from the [official project](https://rojo.space/docs/v7/installation/).
   The projects use the v7 project format and `$attributes` support (introduced in 7.3). Check your build output;
   an import/build error is a setup failure, not a smoke pass.
3. Build one fixture from the repository root, for example:

   ```sh
   rojo build examples/release-smoke/projects/inventory.project.json -o /tmp/inventory-smoke.rbxlx
   python tools/check_engine_evidence.py --digest inventory
   ```

   Open the resulting place in Studio. The `-o` file is a local build artifact, not an execution receipt. Projects
   import original source files through relative paths; don't replace them with snippets pasted from a recipe.
4. In **Edit** mode, set these Workspace attributes through Properties/command bar:
   - `ReleaseSmokeSourceDigest`: exact 64-character digest printed above
   - `ReleaseSmokeEngineVersion`: actual dotted Studio engine version from About Studio
   - `ReleaseSmokeEnabled`: `true`
   Keep the checked-in project JSON unchanged. Changing only these test configuration attributes in the disposable
   place avoids a self-referential source digest. If source or project JSON changes, rebuild, recompute and rerun.
5. Disable unrelated Studio plugins/scripts that modify this disposable scene. Use the default character controller
   and the fixture's StreamingEnabled=false. Streaming-on and real device coverage are separate tests.
6. For `save-system` only: explicitly authorize test DataStore writes/removal, publish this fixture to the dedicated
   test universe, enable Studio API access there, set `ReleaseSmokeAllowDataStore=true`, and set
   `ReleaseSmokeTestUniverseId` to its actual positive universe ID. It must equal `game.GameId`. The driver uses
   only `LuauAISkill_ReleaseSmoke_v1`, a unique `Smoke_<GUID>` key, and removes that key at the end. RemoveAsync is
   recoverable versioned removal, not permanent version deletion. API errors fail the case; there is no memory-only
   fallback. A failed cleanup includes the key in its assertion detail so a maintainer can investigate it.

The default fixture attributes deliberately leave execution/data access disabled. They never contain keys,
passwords, production IDs, third-party assets, or made-up run evidence. Open Cloud execution, publishing and enabling
API access are external actions requiring the operator's appropriate authorization.

## Studio execution

Use **Test → Server & Clients**, with at least the following number of clients. Don't use a single Play client for
cases requiring two. For save-system, Studio **Run** is sufficient after the dedicated-universe setup.

| Case | Minimum clients | Executed assertions | Important limits |
|---|---:|---|---|
| save-system | 0 | Real UpdateAsync acquire, contention rejection, save with uncached readback, release, different-owner reacquisition, unique-key cleanup | Exercises original Schema/SessionLock transforms over the actual DataStore service. Does not start hardcoded PlayerData_v1 Profiles, test player rejoin/autosave/BindToClose, fault injection, receipt purchases, or cross-server races. |
| network-rate-limiter | 2 | Invalid request rejected, valid return values, exhausted budget rejected, independent per-player budgets, exact server counters | Reliable RemoteFunction transport; not unreliable packet loss, sustained load, or disconnect cleanup. |
| inventory | 2 | Invalid slot unchanged, real remote Move, Use consumes and heals, owner snapshot, other player's inventory unchanged | In-memory recipe inventory; not persistence/drop templates/full UI/input devices. |
| interaction | 1 | Tagged prompt creation, actual client prompt activation, disabled and distant attempts unchanged, untag cleanup | A distant normal client attempt can be rejected by the engine before the handler; this is not proof of exploit resistance or server-side LOS rejection. |
| hitscan-gun | 1 | Spoofed origin rejected, real raycast/headshot damage, ammo debit, wall blocks target, reload restores magazine | Original Hitscan/Common/Damage with a primitive target and equipped tool; not lag compensation, PvP/team logic, multi-client cosmetics, or input bindings. |
| round-manager | 2 | Round starts, map clone, client phase/deadline replication, elimination winner, map removal, surviving avatar replaced next cycle | Actual RoundServer script; not disconnect/late join/cross-server matchmaking. Survivor respawn is observed rather than mistaking the eliminated player's automatic respawn for round cleanup. |
| sprint-crouch-stamina | 1 | Real InputAction bindings, crouch/stand/sprint speeds, authoritative stamina drain/recovery, respawn reset | Scriptable InputBinding and scripted Humanoid movement; not physical keyboard/touch/gamepad, headroom, cheat punishment, or extreme latency. |
| npc-patrol | 1 | Tag binds manager, actual path/physics movement, server network ownership, untag stops manager writes | Default R6 rig created from empty HumanoidDescription (no supplied asset IDs). This may use Roblox avatar service; failure is not skipped. Not crowd performance, blocked-path replans, or chase combat. |
| settings-menu | 1 | Actual menu/controls created, sanitization, camera FOV, debounced real save/sync roundtrip, one persistent menu after respawn | Setting changes use ClientSettings, not simulated button events. No claims about click/navigation behavior, mobile layout, persistence across rejoin, or audio bus playback. |
| lighting-presets | 1 | All declared writable Lighting/effect properties converge for all nine presets; no duplicate post effects | Requires nine separately captured client screenshots. Property equality and screenshots do not establish art approval, device-quality equivalence or FPS. |

The default overall deadline is 180 seconds. Individual waits are bounded. The lighting screenshot-paused variant
allows 1200 seconds. Timeout writes a **failed** result; stop/discard the session immediately even if a previously
yielding operation later resumes. A fresh session is required for a retry. Never combine later success with earlier
partial output or edit an assertion to PASS.

### Capturing a run

1. Preserve the server Output/console text for the whole run, including errors/warnings. The server emits exactly
   one terminal line beginning `LUAU_RELEASE_SMOKE_RESULT ` followed by JSON. Keep the original capture and record
   the Studio instance/session ID, mode, client count, actual engine version and capture time.
2. With Studio MCP, first list/select the actual Studio and pass `studio_id` on every call. Start/inspect Server &
   Clients in the supported host. Read server output, client output and capture the relevant client screen. A
   plugin-security `execute_luau` call is an observation/setup tool, not proof of game-script permissions: the
   fixture's game Scripts/LocalScripts must run the assertions. See [Studio testing](../../handbook/roblox/24-studio-mcp-testing.md).
3. Extract the terminal JSON without creating an executed claim:

   ```sh
   python tools/check_engine_evidence.py --extract maintainers/engine-smoke/artifacts/inventory-console.txt > maintainers/engine-smoke/artifacts/inventory-result.json
   ```

4. Inspect failed assertions/errors. Fix durable source, rebuild and rerun; do not patch Play-mode copies. Keep a
   failing-before artifact when correcting an engine bug. Only a new complete passing run can satisfy the gate.
5. Stop the test and close/discard the fixture. Scripts/connections belong to that disposable session; they are
   not intended to be hot-reloaded into a running real game.

This runner doesn't automatically invoke `StudioTestService:EndTest`; the documented baseline is a manual/MCP
Server & Clients session. Don't launch it through the yielding multiplayer test API without a separate completion
adapter. That avoids pretending every MCP host supports the same multiplayer-control flow.

### Lighting captures

Before starting, set `ReleaseSmokePauseForScreenshots=true`. Studio-only LightingStyle and
PrioritizeLightingQuality are declared in the fixture's **Edit-time** project properties; game code does not write
them. The client camera is fixed on primitive walls, blocks and practical lights to make every preset comparable.
For each server Workspace `ReleaseSmokeCapturePreset` value:

1. Capture the actual client view as a nonempty PNG/JPEG, with its current run ID and UTC capture time.
2. In the **server** DataModel, set `ReleaseSmokeCapturedPreset` to that exact preset name to advance.
3. Repeat HorrorInterior, BackroomsOffice, DarkCorridor, NightExterior, Sunset, FogDay, IndustrialWarehouse,
   Poolrooms, EmergencyRed. The deadline is 120 seconds per acknowledgement. Do not reuse one image for multiple
   presets. Review images for missing scene/effects and retain them even if the numeric assertions pass.

The artifact validator checks file integrity/signatures, distinct images, named coverage, run IDs and timestamps.
It does not judge pixels, visual quality, accessibility, or device performance. Actual human visual review and
hardware/graphics-tier acceptance remain outside this minimal smoke gate.

## Open Cloud: save-system only

Open Cloud has no clients or physics and doesn't auto-run the place's Scripts. It **cannot** satisfy any of the
other nine cases. Publish the save fixture to an authorized isolated test place/version and submit a Luau execution
task explicitly against that version. Never put API credentials in this repository, command history, or receipt.
Use your existing authorized secret handling and the official
[Luau execution API reference](https://create.roblox.com/docs/cloud/reference/LuauExecutionSessionTask).

The task script explicitly sets the same attributes and calls the actual ModuleScript. Replace the placeholders
from the real test configuration; do not paste production identifiers:

```luau
-- fragment: Open Cloud task body; requires the published save-system fixture and operator-supplied values.
workspace:SetAttribute("ReleaseSmokeEnabled", true)
workspace:SetAttribute("ReleaseSmokeOpenCloud", true)
workspace:SetAttribute("ReleaseSmokeAllowDataStore", true)
workspace:SetAttribute("ReleaseSmokeTestUniverseId", TEST_UNIVERSE_ID)
workspace:SetAttribute("ReleaseSmokeSourceDigest", CURRENT_DIGEST)
-- version() is deprecated, retained here only as a diagnostic for actual runtime provenance.
-- RunService:GetRobloxVersion is security-restricted and is not an ordinary script substitute.
workspace:SetAttribute("ReleaseSmokeEngineVersion", version())
return require(game.ServerScriptService.ReleaseSmoke.Run).run()
```

Poll the actual task to terminal state. Retain the full task resource JSON and all log pages before the service's
retention window expires. Join the returned log `messages` entries in order into the UTF-8 capture file, preserving
the original provider JSON separately. The task must be COMPLETE, have no error, and contain the exact result table
in `output.results[1]`; QUEUED/PROCESSING are pending, never passes. Record the full version-specific task resource
path and the observed positive place version. No cloud adapter, credentials or provider task was executed here.

## Receipt files and manifest promotion

Use a directory under `maintainers/engine-smoke/artifacts/` (not committed fake artifacts). Every artifact reference
is an object containing a path **relative to this directory's parent, `maintainers/engine-smoke/`**, plus its lowercase
SHA-256. Paths may not escape this directory or use absolute paths. Calculate hashes from captured bytes, for example:

```sh
python -c "import hashlib,pathlib; p=pathlib.Path('maintainers/engine-smoke/artifacts/inventory-console.txt'); print(hashlib.sha256(p.read_bytes()).hexdigest())"
```

A Studio receipt's structure is below. The angle-bracket text is intentionally invalid placeholder data, not an
executed sample. `result` is the extracted JSON; `capture` is the separately retained raw server text.

```json
{
  "schema_version": 1,
  "label": "STUDIO TESTED",
  "result": {"path": "artifacts/inventory-result.json", "sha256": "<actual hash>"},
  "capture": {"path": "artifacts/inventory-console.txt", "sha256": "<actual hash>"},
  "runner": {
    "environment": "studio-server-clients",
    "id": "<actual studio/session ID>",
    "mode": "Server & Clients",
    "clients": 2,
    "engine_version": "<actual dotted engine version>"
  },
  "screenshots": {}
}
```

For lighting, `screenshots` must contain exactly all nine preset names. Each value has `path`, `sha256`, `run_id`
matching the result, and ISO `captured_at` between the result's start/end times. For Cloud, use label
`CLOUD EXECUTED`, runner environment `open-cloud`, actual task path as `runner.id`, positive `runner.place_version`,
and `task: {"path": "artifacts/save-execution.json", "sha256": "<actual hash>"}`. The captured engine version must agree.

After reviewing a successful run, add the receipt file's own path/hash object to that case's `receipts` array in
[manifest.json](manifest.json), set its `status` to the matching evidence label and clear `blocker`. Do not copy
synthetic unit-test data. The manifest is only an index; a status label alone never passes. Validate with the default
command. A changed source digest, missing artifact, hash mismatch, failed/skipped assertion, wrong engine/client
mode, duplicate run ID, old PASS followed by later failure in the same capture, or incomplete lighting screenshots
blocks release. The digest binds original recipe-family Luau, shared library, harness, fixture project and source
lock. It does not attest the publisher's identity or cryptographically prove those bytes were deployed: maintainers
must verify deployment/source provenance and retain original external captures. Handwritten/fabricated evidence is
not acceptable even if a syntactically valid receipt could be constructed.

## Static API verification and extension policy

APIs were inspected with `tools/api.py` and the pinned creator-docs sources, including DataStoreGetOptions.UseCache,
GlobalDataStore.UpdateAsync/GetAsync/RemoveAsync, ProximityPrompt.InputHoldBegin/InputHoldEnd, InputBinding.Fire
with Scriptable type, Humanoid.Move, Players.CreateHumanoidModelFromDescriptionAsync, network ownership, RunService
and replication APIs. InputAction.Fire was rejected as deprecated in favor of the verified scriptable binding.
RunService.GetRobloxVersion was rejected for game-script security. Open Cloud task states, output and resource paths
were checked against the pinned `reference/cloud/openapi.json` through the repository source lock.

Rojo format references: [project format](https://rojo.space/docs/v7/project-format/),
[upstream project parsing](https://github.com/rojo-rbx/rojo/blob/master/src/project.rs),
[attribute support changelog](https://github.com/rojo-rbx/rojo/blob/master/CHANGELOG.md).

When adding checks, update the executable driver, fixed validator requirements and manifest together; add validator
regressions and retain honest coverage limits. Never loosen a gate just because Studio is unavailable. See
[SKILL evidence labels](../../SKILL.md#evidence-labels-use-in-reports-and-code-headers).
