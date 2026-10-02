# Community ecosystem: versions, status, and how to write code inside each

Read when: the project already uses a library/tool below (check `wally.toml`, `pesde.toml`, `default.project.json`,
`Packages/`, `aftman.toml`/`rokit.toml`, requires of `Knit`, `Fusion`, `React`, `jecs`…). This skill doesn't push
frameworks; it makes sure code written **inside** one follows that library's model and the installed version.

Checked 2026-10-02 (latest tags via `git ls-remote`; maintenance notes from the repositories' READMEs, plus GitHub
archive flags and release dates collected the same day by the maintainers' research pass). Versions move — the
project's lockfile wins over this table. Never upgrade or swap a dependency unasked.

## Rules for any library
1. Find the **installed** version (lockfile, `Packages/_Index`, the module's own version field) and read that
   version's API; don't mix idioms from other major versions.
2. Generated code (Blink/Zap output, darklua builds, `Packages/`) is never edited by hand — change the source/schema
   and regenerate.
3. A library's serializer/validator checks **shape**, not **permission**: server-side gameplay validation still applies.
4. Archived/unsupported ≠ broken: keep working code; mention the status and a migration only if asked or relevant.

## Frameworks, UI, ECS
| Library | Latest seen | Status | Mental model | AI pitfalls |
|---|---|---|---|---|
| Knit (Sleitnick) | v1.7.0 | **archived** ("No longer maintained") | services (server) / controllers (client), `KnitInit` → `KnitStart`, `Knit.Start()` promise; `Client` table on a service = remote API | `Client` methods are a network boundary — validate args like any remote; don't call other services before `KnitStart`; don't migrate a Knit game to another framework unasked |
| Fusion | v0.3-beta (tag; GitHub marks it non-prerelease) | unclear activity | reactive state; 0.3 = **scopes** own lifetimes, `use`/`peek` read state | don't mix 0.2 (`Value:get()`, `New` without scope, `Cleanup`) with 0.3 (`scope:Value`, `scope:New`, `use`); every created object needs a scope that gets cleaned up |
| React-lua (jsdotlua) | v17.2.1 | unclear activity | React 17 port: components, hooks, `ReactRoblox.createRoot` | don't use Roact (`Roact.mount`) APIs or JS-only React APIs; effects must return cleanup; keys for lists |
| Jecs | v0.11.0 (2026-03) | active | archetype ECS: entities are numbers, components/pairs, `world:query(...)` | entity ids aren't Instances; v0.11 forbids structural changes in `on_remove` hooks — defer them; use the pinned API |
| Matter | 0.8.x (README) | unclear | ECS with a scheduler `Loop`, `world:query`, hooks-like topologically-aware state | don't port Jecs code by renaming; follow the project's system/loop setup |

## Data and networking
| Library | Latest seen | Status | Mental model | AI pitfalls |
|---|---|---|---|---|
| ProfileStore (MadStudio) | no semver tags; default branch | supported successor of ProfileService | session-locked profiles, autosave; `ProfileStore.New` → `:StartSessionAsync(key, …)`, `profile:EndSession()`, `OnSessionEnd` | stop writing after the session ends; receipts: acknowledge only after the save that contains the `PurchaseId` is confirmed, not after mutating `Profile.Data` |
| ProfileService | — | **unsupported** (README: use ProfileStore for new projects) | predecessor: `LoadProfileAsync`, `:Release()`, `ListenToRelease`, global updates | its internal "ProfileStore" object is not the new library; ProfileService → ProfileStore is a migration with data-key and lifecycle review, never a text rename |
| Blink | v0.18.x stable; v1.0.0-pre.10 tags exist | active | schema (`.blink`) → generated typed buffer networking for both peers | edit the schema, regenerate both sides with the same compiler version; generated range checks ≠ gameplay validation |
| Zap | v0.6.29 (2026-06) | active | schema (`.zap`) → generated networking code | same as Blink; respect the installed syntax; since 0.6.29 generated code can be required in Edit mode |
| ByteNet | v0.4.3 (2024, prerelease) | unclear | runtime packet definitions + namespaces | match packet definitions on both peers exactly; prerelease semantics |

## Toolchain
| Tool | Latest seen | Status | Notes / pitfalls |
|---|---|---|---|
| Rojo | v7.7.1 (2026-10-02) | active | disk is the source of truth; 7.7 adds explicit **syncback** (Studio → disk). Studio-MCP edits to synced scripts get overwritten — edit files |
| Wally | v0.3.2 (2023); v0.4.0-alpha tags | slow | `wally.toml` + `wally.lock`; realms shared/server/dev; never edit `Packages/` |
| pesde | v0.7.4 tag (v0.7.3 released 2026-03) | active | `pesde.toml` with runtime targets; don't transplant Wally `Packages` paths |
| Lune | v0.10.5 (2026-07) | active | standalone Luau runtime with fs/process/net and Roblox file (de)serialization — **not the engine**; embeds Luau 0.709 → newer syntax may not parse; label runs CLI-EXECUTED |
| Selene | 0.32.0 tag (0.31.0 released 2026-05) | active | linter with Roblox std; lint pass ≠ typecheck ≠ runtime |
| StyLua | v2.5.2 (2026-05) | active | formatter; keep reformatting out of behaviour-fix diffs |
| darklua | v0.19.0 (2026-06) | active | AST transforms/bundling (string requires → instance paths, etc.); edit source, rerun the pipeline |
| luau-lsp | 1.70.1 (2026-09-27) | active | typecheck/LSP with Roblox definitions + sourcemap; pin definitions with the binary |

## Testing
| Tool | Latest seen | Status | Notes |
|---|---|---|---|
| Jest-Lua (jsdotlua) | v3.10.0 (2024-12) | stable | runs **only inside Roblox** (Studio/run-in-roblox/Open Cloud), not under Lune; not all JS Jest matchers exist |
| TestEZ (Roblox) | v0.4.2 (2022) | archived (2024-09) | keep existing suites; don't start new ones on it |
| run-in-roblox | v0.3.0 (2020) | unclear | launches a real Studio with `--place`/`--script`; not headless, Windows/macOS only in practice |
| Open Cloud Luau Execution | API (stable) | official | headless server-side tasks on a place version — [details](../handbook/roblox/24-studio-mcp-testing.md#ci-without-studio-open-cloud-luau-execution) |
| OpenGameEval (Roblox) | repo | official | benchmark harness for AI game-dev tasks in Studio; needs an Open Cloud key with `studio-evaluations` |

Sources: cd:projects/external-tools, cd:scripting/sync. Repositories: github.com/Sleitnick/Knit, dphfox/Fusion,
jsdotlua/react-lua, Ukendio/jecs, matter-ecs/matter, MadStudioRoblox/ProfileStore, MadStudioRoblox/ProfileService,
1Axen/blink, red-blox/zap, ffrostfall/ByteNet, rojo-rbx/rojo, UpliftGames/wally, pesde-pkg/pesde, lune-org/lune,
Kampfkarren/selene, JohnnyMorganz/StyLua, seaofvoices/darklua, JohnnyMorganz/luau-lsp, jsdotlua/jest-lua,
Roblox/testez, rojo-rbx/run-in-roblox, Roblox/open-game-eval.
