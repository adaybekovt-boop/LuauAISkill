# Track: Luau language

Use for: syntax/type questions, pure modules, data structures, coroutines/`task`, Luau-level performance.
Load: [01 core](../handbook/luau/01-language-core.md) → [02 types](../handbook/luau/02-types.md) →
[03 syntax & stdlib](../handbook/luau/03-syntax-stdlib.md) → as needed [04 patterns](../handbook/luau/04-patterns-data.md),
[05 coroutines/task/errors](../handbook/luau/05-coroutines-task-errors.md), [06 performance](../handbook/luau/06-performance-memory.md).

Non-negotiables
- Luau ≠ Lua 5.x: `continue`, compound assignment, `if-then-else` expressions, string interpolation, `const`, generics;
  no `goto`, no integer subtype, no `io`/`os.execute`.
- `task.wait/spawn/defer/delay`, never `wait/spawn/delay`.
- Types don't validate runtime data; `--!strict` + explicit validation for untrusted input.
- Old vs new type solver differ: keep code valid under both unless the project pinned one.
- Luau CLI ≠ Roblox: `script`, `game`, `warn`, `Instance` don't exist in the CLI; require-by-string works in both.

Verify: `python tools/check_code.py path/to/file.md`; pure modules → a `*.spec.luau` run with the Luau CLI.
Failure modes: [§2 other languages leaking in](../references/ai-failure-modes.md#2-other-engines--other-languages-leaking-in).
Evals: `evals/cases/luau.jsonl`.
