# Track: networking & security

Use for: remotes, replication, anti-exploit, validation, server authority mode.
Load: [networking](../handbook/roblox/03-networking.md) → [security](../handbook/roblox/04-security.md) →
[server authority mode](../handbook/roblox/05-server-authority.md) if the project uses it → [limits](../references/limits.md).

Non-negotiables
- Client sends intent; server validates (rate → types/ranges incl. NaN/inf → state → distance/LOS → act).
- `OnServerEvent(player, ...)`: the engine supplies `player`; never trust a player argument in the payload.
- No `InvokeClient` on critical paths; `RemoteFunction` handlers must not yield long.
- Server-created remotes only; per-player per-action limits; clear per-player state on leave.
- Unreliable remotes: cosmetic, ≤ 1000 bytes. ≈500 req/s per client cap across remotes of a type.
- Balanced anti-cheat: validate outcomes that matter; log + review before punishing heuristics.

Recipes: [network-rate-limiter](../recipes/gameplay/network-rate-limiter.md), [interaction-system](../recipes/gameplay/interaction-system.md),
[hitscan-gun](../recipes/gameplay/hitscan-gun.md). Verify with the recipes' exploit tables.
Evals: `evals/cases/networking.jsonl`, `evals/cases/security.jsonl`.
