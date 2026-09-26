# Track: project architecture & code quality

Use for: starting a project, placing scripts, structuring modules, refactoring, reviews, tooling choices.
Load: [runtime architecture](../handbook/roblox/01-runtime-architecture.md) → [lifecycle & events](../handbook/roblox/02-lifecycle-events.md)
→ [architecture](../handbook/roblox/21-architecture.md) → [code quality](../handbook/roblox/22-code-quality.md) →
[tooling & testing](../handbook/roblox/23-tooling-testing.md); [service map](../references/service-map.md) for "which service".

Non-negotiables
- Inspect the existing project first (structure, conventions, sync tool, lifecycle pattern) and follow it.
- Simplest structure that fits: services/modules with explicit `start()`, one entry script per side; no framework
  unless the project already has one.
- Every connection/instance/thread has an owner and cleanup (Cleanup/Binder patterns in `examples/lib`).
- Server-only code in ServerScriptService/ServerStorage; shared in ReplicatedStorage; client in StarterPlayerScripts
  (or client `Script` with RunContext Client in ReplicatedStorage).
- Don't hide failures (`pcall` without handling), don't add side effects at require time without a reason.

Recipes: pick from [recipes/INDEX.md](../recipes/INDEX.md) instead of inventing structure.
Verify: `check_code.py`, `check_api_refs.py`, Selene/StyLua/luau-lsp if the project uses them (optional).
Evals: `evals/cases/architecture.jsonl`.
