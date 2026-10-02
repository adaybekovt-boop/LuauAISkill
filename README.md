# LuauAISkill — modern Roblox + Luau engineering skill for AI agents

An inference-time skill (knowledge + tools) that makes AI coding agents write **current, secure, measurable**
Roblox Studio / Luau code and art-direct scenes — instead of 2019-era patterns, invented APIs and fake test claims.
Snapshot: **2026-10-02** · engine API **0.741.19** · creator-docs `578b33e` · luau-lang/site `a60a627`.
Русская версия: [README_RU.md](README_RU.md).

> This is documentation + tooling, not a fine-tuned model. It improves answers only when the agent loads the right
> files; measure with the evals rather than trusting a percentage.

## What's inside
| Path | Content |
|---|---|
| [`SKILL.md`](SKILL.md) | entry point: workflow (incl. Studio MCP verification), hard rules, evidence labels, routing, freshness snapshot |
| [`tracks/`](tracks/INDEX.md) | 17 task routes: which files to load for networking, data, graphics, combat, NPC… |
| [`handbook/`](handbook) | 39 chapters: `luau/` (6), `roblox/` (26), `graphics/` (7) — dense tables, decision trees, typechecked code |
| [`recipes/`](recipes/INDEX.md) | 20 gameplay + 15 graphics end-to-end recipes (architecture, full code, tests, exploit checks) |
| [`examples/`](examples) | recipe code as Rojo-style projects (`examples/<project>/<Service>/…`), shared `lib/`, Luau CLI tests |
| [`references/`](references) | legacy→current catalog (89 entries), community ecosystem (versions, status, pitfalls), AI failure modes, anti-patterns, debugging playbook, limits, service map |
| [`api/`](api) | generated engine API index (classes, members, enums, datatypes, deprecations, summaries) |
| [`evals/`](evals/README.md) | categorized eval cases incl. broken-code fixtures and adversarial prompts + rubric |
| [`tools/`](tools) | API lookup, legacy scanner, search, checkers, source fetch/lock, embed tool |
| [`sources/`](sources) | pinned upstream commits (`lock.json`), toolchain versions, resolved source registry |
| `maintainers/` | gap report and maintainer notes (not needed at runtime) |

## Install as a skill
- **Claude Code**: copy or clone this repository to `~/.claude/skills/tk-luau-roblox/` (personal) or
  `<project>/.claude/skills/tk-luau-roblox/` (project). The agent reads `SKILL.md` when a Roblox/Luau task comes up;
  tool paths resolve through `${CLAUDE_SKILL_DIR}`, so the tools work from any project directory.
- **Claude apps (claude.ai / Desktop)**: zip a folder named `tk-luau-roblox/` containing the repository and upload it
  under Customize → Skills. The frontmatter uses only portable fields (`name`, `description`, `license`,
  `compatibility`, `metadata`), so upload validation accepts it. Leave out `.cache/` and `.git/`.
- **Studio MCP**: if Roblox Studio's MCP server is connected to the agent, the skill uses it to reproduce and verify
  fixes ([handbook/roblox/24-studio-mcp-testing.md](handbook/roblox/24-studio-mcp-testing.md)).
- **Other agents** (Codex, Cursor, custom): point the agent's instructions at `SKILL.md`; `AGENTS.md` does that for
  tools that read it.
- Python 3.10+ is enough for `tools/api.py`, `tools/search.py`, `tools/scan_legacy.py` (the API index is committed).

## Everyday tools
```text
python tools/api.py Humanoid.LoadAnimation        # exists? deprecated? what replaces it?
python tools/api.py Lighting.LightingStyle        # can a game script write it?  (no: Studio/plugin only)
python tools/api.py --search Pathfinding          # find classes/members/enums
python tools/scan_legacy.py path/to/src           # legacy patterns with catalog ids (read-only)
python tools/search.py "session locking"          # ranked search over the skill
python tools/check_api_refs.py my-notes.md        # validate API names in any Markdown/Luau
```

## Verification status (honest)
| Check | Result (2026-10-02) | How to reproduce |
|---|---|---|
| Luau code blocks in Markdown | typechecked with luau-lsp 1.70.1 + Roblox defs, strict, old **and** new solver | `python tools/check_code.py` |
| Example projects (`examples/`) | 70 files typechecked (same settings) | same |
| Pure logic tests | 9 suites, 51 tests executed with Luau CLI 0.740 | same (runs `examples/tests/*.spec.luau`) |
| API references in all text/code | 0 unknown / 0 unmarked deprecated | `python tools/check_api_refs.py` |
| Source citations (`cd:`, `luau:`, `api:`) | all resolve against pinned sources | `python tools/check_sources.py` |
| Links and anchors | checked | `python tools/check_links.py` |
| Tool unit tests | `tests/` (Python unittest) | `python -m unittest discover tests` |
| **Roblox Studio / live servers** | **nothing was run in Studio or live** | follow each recipe's "How to test" |
Visual presets are art-direction starting points; property names/types are validated, the look is not
screenshot-verified.

## Updating to newer Roblox versions (non-destructive)
```text
python tools/install_toolchain.py                 # pinned luau + luau-lsp → .cache/bin
python tools/fetch_sources.py --latest            # newest creator-docs / API dump / luau site → updates sources/lock.json
python tools/build_api_index.py                   # regenerate api/
python tools/check_all.py                         # everything above + API refs, sources, links, legacy catalog
git diff api/deprecated.tsv api/classes.tsv       # review what changed; update chapters/catalog by hand
```
Nothing is overwritten except generated files (`api/`, `sources/registry.json`, `qa/`); authored text changes only
through your edits.

## Limitations
- Knowledge is a snapshot; beta features (CCL default/custom abilities, `InputActionLabel`, LibMP, the Studio playtest
  agent) change. A weekly CI job (`.github/workflows/freshness.yml`) opens an issue when the engine API drifts.
- Some engine APIs exist in the dump without docs (`tools/api.py` marks them UNDOCUMENTED); the skill avoids them.
- Nothing in this repository was run in Studio. Agents with Studio MCP can verify their own changes; feel and visuals
  still need a human on target devices.
- Skill content is English (compact, exact API names); agents answer in the user's language.

## License
Text CC BY 4.0, code MIT; third-party attribution in [NOTICE.md](NOTICE.md). Not affiliated with Roblox Corporation.
