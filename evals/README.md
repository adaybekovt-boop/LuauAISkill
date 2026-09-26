# Evals: does the skill actually make answers better?

135 cases in 16 categories (`cases/<category>.jsonl`), 15 broken-code fixtures (`fixtures/`), an automatic
pre-grader (`grade.py`) and a rubric ([RUBRIC.md](RUBRIC.md)). No results are committed: a score only means
something with the model, date, skill version and grader named next to it.

| Category | Cases | Focus |
|---|---|---|
| luau | 13 | types vs validation, truthiness, tables, `task`, hosts (incl. a Russian prompt) |
| architecture | 8 | structure without frameworks, containers, lifecycle, cleanup, reviews |
| networking | 10 | remote validation order, reliability choice, ordering, payload design |
| security | 10 | exploited handlers (fixtures), secrets, anti-cheat without false bans |
| datastores | 10 | data loss fixture, session locking, receipts fixture, migrations, caches |
| performance | 8 | NPC loop / pathfinding / memory-leak fixtures, measurement discipline |
| graphics | 8 | hallucinated lighting fixture, impossible features, tiers, mood recipes |
| lighting | 8 | Studio-only properties, limits, ownership, flashlight/flicker |
| ui | 6 | offset-layout fixture, gamepad/touch, accessibility, settings |
| combat | 6 | Touched-bullet fixture, hitscan, knockback ownership, ragdoll |
| npc | 5 | fair AI, MoveTo timeout, Blocked replans, ownership, crowds |
| animation | 5 | Animator, replication, head-bob fixture, footsteps |
| streaming | 6 | direct-index fixture, Studio-only settings, teleports, determinism |
| debugging | 8 | symptom → cause → check |
| api-freshness | 12 | legacy grab-bag fixture, `*Async` renames, removed enums, undocumented/beta APIs |
| adversarial | 12 | pressure to fake tests, use deprecated/hallucinated APIs, leak secrets, invent metrics |

## Case format
```json
{"id": "NET-01", "category": "networking", "kind": "task|knowledge|fixture|adversarial", "lang": "en|ru",
 "prompt": "...", "fixture": "evals/fixtures/x.luau", "must": ["..."], "must_not": ["..."], "critical": "...",
 "auto": {"forbid": ["regex (code blocks only)"], "require_any": ["regex (whole answer)"]}, "refs": ["skill files"]}
```
`must`/`must_not`/`critical` are for the grader (human or judge model); `auto` is a cheap pre-screen;
`refs` tell maintainers which skill files should make the case pass.

## Protocol (A/B)
1. Pick a model and freeze its settings. Condition A: no skill. Condition B: the skill available (SKILL.md loaded,
   agent allowed to read files and run `tools/api.py`).
2. For each case: `python evals/grade.py --print <ID>` gives the exact prompt (+ fixture). Save the model's answer
   as `<run>/<ID>.md`.
3. `python evals/grade.py <run> --name <model>-<A|B>` → automatic flags (hallucinated/deprecated APIs in code,
   forbidden patterns, missing required facts, wrong language). Results go to `evals/runs/` (gitignored).
4. Score every answer with [RUBRIC.md](RUBRIC.md) **blind** to the condition (shuffle, hide file names).
5. Report per category: mean score A vs B, critical failures A vs B, number of cases, grader, model/version, date.
   Don't generalize beyond the tested model and categories.

## Adding cases
Prefer realistic broken code (a fixture) over trivia; one clear critical failure per case; `forbid` regexes only
for code-level mistakes (they are applied to code blocks); fixtures start with `-- BAD`/`-- LEGACY` so repository
checks treat them as intentional.
