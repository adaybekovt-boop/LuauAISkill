# Track: testing & verification

Use for: adding tests, CI, lint/typecheck setup, proving a change works, playtesting through Studio MCP.
Load: [tooling & testing](../handbook/roblox/23-tooling-testing.md) → [Studio MCP, multiplayer, Open Cloud](../handbook/roblox/24-studio-mcp-testing.md)
(when Studio MCP tools are connected or CI needs the engine) → [ecosystem](../references/ecosystem.md) (Jest-Lua/TestEZ/Lune).

Evidence ladder (report the highest you actually reached): STATIC VERIFIED (read + API index) → TYPECHECKED (luau-lsp
with Roblox defs) → CLI-EXECUTED (pure logic under the Luau CLI) → CLOUD EXECUTED (Open Cloud Luau Execution) →
STUDIO TESTED (Play / Server & Clients, with artifacts) → LIVE TESTED (published servers). NOT RUN when nothing ran.
- Studio MCP connected → `list_roblox_studios` → `studio_id` on every call → reproduce, patch the source of truth,
  re-run the same assertions; `execute_luau` runs with plugin security (not proof that a game script may call it).
- Pure logic → `.spec.luau` tests runnable by the Luau CLI (see `examples/tests`).
- Roblox code → typecheck with Roblox definitions; then Studio tests from the recipe's test table.
- This repo: `python tools/check_all.py` runs every check (see README).

Additional verified examples: [multiplayer-regression-harness](../recipes/gameplay/multiplayer-regression-harness.md).
