# Track: testing & verification

Use for: adding tests, CI, lint/typecheck setup, proving a change works.
Load: [tooling & testing](../handbook/roblox/23-tooling-testing.md).

Evidence ladder (report the highest you actually reached): STATIC VERIFIED (read + API index) → TYPECHECKED (luau-lsp
with Roblox defs) → CLI-EXECUTED (pure logic under the Luau CLI) → STUDIO TESTED (Play / Server & Clients) →
LIVE TESTED (published servers). NOT RUN when nothing ran.
- Pure logic → `.spec.luau` tests runnable by the Luau CLI (see `examples/tests`).
- Roblox code → typecheck with Roblox definitions; then Studio tests from the recipe's test table.
- This repo: `python tools/check_all.py` runs every check (see README).
