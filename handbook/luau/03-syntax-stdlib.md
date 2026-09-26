# Modern Luau syntax and standard library (Roblox, 2026)

Read when: choosing idioms, using library functions, reviewing code written from pre-2021 memory.
Related: [core](01-language-core.md), [performance](06-performance-memory.md).

## Syntax available in Roblox (verified in Luau 0.740 docs + Roblox docs)
| Feature | Example | Note |
|---|---|---|
| Type annotations | `local hp: number = 100` | [types](02-types.md) |
| `const` binding | `const MAX = 100` | binding cannot be reassigned; table contents still mutable; `const` is contextual (old `local const = 1` still parses) |
| Compound assignment | `n += 1`, `s ..= "x"` | statement only |
| `continue` | `if skip then continue end` | |
| If-expression | `local c = if hp > 50 then "ok" else "low"` | use instead of `a and b or c` |
| String interpolation | `` `Score: {score}` `` | no `{{`; use `\{` to print a brace |
| Generalized iteration | `for k, v in t do` | same speed as pairs/ipairs; order unspecified for dictionaries |
| Floor division | `x // 2` | floors toward −∞ |
| Function attributes | `@native local function hot() end`, `@deprecated` | `@native` = native codegen hint; `@deprecated` makes the linter warn callers |
| Explicit generic instantiation | `identity<<number>>(5)` | rarely needed |
| Require by string | `require("./Util")`, `require("@game/ReplicatedStorage/Shared/Net")` | `./`=script.Parent, `../`, `@self/`=script, `@game/`; **non-blocking**: errors if the module is not there yet |

Upstream Luau experiments (not a baseline): anything not in the Roblox docs for your Studio build. Check with a
tiny probe script before adopting syntax in a shared codebase.

## task library (use instead of wait/spawn/delay)
| Function | Behaviour |
|---|---|
| `task.wait(s?)` | yields ≥ s seconds (default one frame, resumes on Heartbeat); returns elapsed time |
| `task.spawn(f, ...)` | runs `f` **immediately** until its first yield; returns the thread |
| `task.defer(f, ...)` | runs `f` later in the current resumption cycle (after current code), no immediate re-entrancy |
| `task.delay(s, f, ...)` | runs after ≥ s seconds; returns thread (cancel with `task.cancel`) |
| `task.cancel(thread)` | cancels a scheduled/suspended thread |
| `task.desynchronize()` / `task.synchronize()` | switch parallel/serial phase (Actors only) |
Legacy `wait()`/`spawn()`/`delay()` are deprecated: throttled, run on a 30 Hz legacy scheduler, and `spawn` had an
implicit delay. Migrating `spawn(f)` → `task.defer(f)` preserves "later" semantics; → `task.spawn(f)` changes order.

## table
`table.create(n, v?)` presized array · `table.find(t, v, init?)` linear search → index · `table.clone(t)` shallow ·
`table.freeze(t)` / `table.isfrozen(t)` shallow read-only · `table.clear(t)` keeps capacity (reuse buffers) ·
`table.move(a, f, e, t, dst?)` · `table.insert/remove` (O(n) when not at end) · `table.sort(t, lt?)` not stable;
comparator must be a strict weak order (`a < b`, never `<=` → "invalid order function" errors) ·
`table.concat(strings, sep)` · `table.pack/unpack`. `table.getn/foreach/foreachi` are legacy — don't use.

## string
`string.split(s, sep)` (Roblox/Luau) · `string.format` (`%s` requires a string/number — wrap with `tostring`;
`%q` quotes) · `string.find/match/gmatch/gsub` use **Lua patterns**, not regex (`%d`, `%a`, `%s`, `-` lazy; no `|`,
no `{n}`) · `string.rep`, `string.sub` (1-based, negative from end) · `string.byte/char` · `string.pack/unpack`
(binary). For UTF-8 text: `utf8.len`, `utf8.codes`, `utf8.char`, `utf8.offset`, `utf8.graphemes` (Roblox).
Build big strings with `table.concat` or `buffer`, not repeated `..` in a loop.

## math
`math.clamp(x, lo, hi)` · `math.round` (half away from zero) · `math.sign` · `math.noise(x, y?, z?)` (Perlin,
returns ~[-1,1], integer inputs return 0 — offset by fractions) · `math.lerp(a, b, t)` · `math.map(x, inMin, inMax,
outMin, outMax)` · `math.isnan/isinf/isfinite` · `math.random(m?, n?)` (global RNG — prefer `Random.new(seed)` for
reproducibility) · `math.huge` · `math.pi`, `math.tau`.

## Random (Roblox datatype) — use for gameplay/procedural RNG
```luau
local rng = Random.new(12345)          -- deterministic per seed, independent stream
local roll = rng:NextInteger(1, 6)     -- inclusive
local f = rng:NextNumber(0.5, 1.5)
local dir = rng:NextUnitVector()
local shuffled = { "a", "b", "c" }
rng:Shuffle(shuffled)
local fork = rng:Clone()               -- same state, independent future
print(roll, f, dir, fork:NextNumber())
```

## buffer (binary data, replicates over remotes, fixed size)
```luau
local b = buffer.create(12)
buffer.writef32(b, 0, 1.5)
buffer.writeu16(b, 4, 65535)
buffer.writestring(b, 6, "hi")
buffer.writebits(b, 8 * 8, 3, 5)       -- bit offset, bit count, value (Luau 2025+)
local x = buffer.readf32(b, 0)
local len = buffer.len(b)
print(x, len, buffer.readbits(b, 64, 3), buffer.tostring(b):len())
```
Out-of-range offsets throw — validate lengths before reading untrusted buffers ([networking](../roblox/03-networking.md)).

## vector (native 3-float value type)
`vector.create(x, y, z)`, `vector.magnitude`, `vector.normalize`, `vector.dot`, `vector.cross`, `vector.lerp`,
`vector.floor/ceil/abs/sign/clamp/min/max`, `vector.zero/one`. In Roblox, `Vector3` is the engine type used by
properties; `vector` functions are fastcalls usable in hot math.

## bit32
`bit32.band/bor/bxor/bnot/lshift/rshift/arshift/extract/replace/btest/countlz/countrz/byteswap`. Operates on
unsigned 32-bit; results are numbers. Use for flags packing and hashing.

## coroutine
`coroutine.create/resume/yield/status/wrap/running/isyieldable/close`. In Roblox prefer `task.*` to schedule;
use raw coroutines for generators/iterators. Don't `coroutine.resume` a thread that engine APIs yielded (use
`task.spawn`) — see [05](05-coroutines-task-errors.md).

## os / debug (Roblox subset)
`os.clock()` high-res CPU-time-ish timer for profiling durations · `os.time()` UTC epoch seconds (integer) ·
`os.date(fmt, t)` · `os.difftime`. No `os.execute/getenv/remove`.
`debug.traceback()`, `debug.info(f|level, "sln")`, `debug.profilebegin(label)` / `debug.profileend()` (MicroProfiler
labels), `debug.setmemorycategory(tag)` / `debug.resetmemorycategory()`.

## Roblox time sources
| Need | Use |
|---|---|
| duration measurement on one machine | `os.clock()` |
| game-time since server start (same scale on server & client, not synced) | `time()` / `workspace.DistributedGameTime` |
| synchronized clock across server & clients | `workspace:GetServerTimeNow()` |
| wall clock / persistence timestamps | `os.time()` or `DateTime.now().UnixTimestampMillis` |
`tick()` is legacy (local timezone-dependent); don't use it for new code.

Verify: probes in `examples/tests/language_facts.spec.luau` (run by `tools/check_code.py`).
Sources: luau:getting-started/syntax, luau:reference/library, luau:reference/attributes, cd:reference/engine/libraries/task,
cd:reference/engine/libraries/buffer, cd:reference/engine/libraries/vector, cd:reference/engine/libraries/math,
cd:reference/engine/datatypes/Random, cd:reference/engine/globals/LuaGlobals, cd:reference/engine/globals/RobloxGlobals,
cd:luau/variables.
