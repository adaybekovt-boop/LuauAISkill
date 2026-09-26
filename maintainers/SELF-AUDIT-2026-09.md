# Self-audit (2026-09-26): a fresh agent using only this repository

Method: for 10 typical requests, follow SKILL.md → tracks/INDEX.md → the track's files, run `tools/search.py` with the
user's words and the tools the workflow requires; record whether the needed facts/code were reachable and correct.
This checks retrieval and coverage — it is not a model-quality measurement (use `evals/` for that).

| # | Request | Route found | Result | Fix made |
|---|---|---|---|---|
| 1 | "Make my horror map lighting realistic" | graphics track → lighting chapters → cinematic-horror-interior | preset + light plan + sound + mistakes | — |
| 2 | "Players lose data sometimes" | data track → save-system (search rank 1) | causes, session lock, tested transforms | — |
| 3 | "Make a PvP gun" | combat track → hitscan-gun | full client/server code, exploit table, lag-comp plan | — |
| 4 | "80 zombies lag the server" | npc/performance tracks → npc-patrol | manager + LOD + mover | — |
| 5 | "Modernize this old script" | legacy track → scan_legacy + catalog | 10 findings on the legacy fixture | `scan_legacy.py` now accepts a single file (it required a directory) |
| 6 | "Mobile UI broken, no gamepad" | ui track → 18-ui-ux | rules present; recipes: settings/inventory UI | — |
| 7 | "Add a day/night cycle" | graphics track → lighting-controller | only an ownership rule existed | added a typechecked server-attribute + client-computed ClockTime cycle |
| 8 | "Sprint with stamina" | character-camera track → sprint recipe | complete, tested stamina model | — |
| 9 | "Teleport a party to a reserved server" | data track → cross-server chapter, matchmaking recipe | TeleportOptions + roster pattern | — |
| 10 | "Is Humanoid:LoadAnimation deprecated?" | `tools/api.py` | deprecated, message names Animator:LoadAnimation | removed the misleading "-> use LoadAnimation" hint when the dump's preferred name equals the member name |

Remaining weaknesses seen during the audit: no recipes for chat/TextChatService commands, leaderboards UI, vehicles,
tools/viewmodels, or server-authority-mode projects (handbook coverage only); visual presets are unverified by
screenshots; nothing is Studio-tested.
