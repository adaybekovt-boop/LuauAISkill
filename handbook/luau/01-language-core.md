# Luau language core (not Lua 5.x)

Read when: writing any Luau; porting Lua 5.1–5.4 / JS / Python habits. Related: [types](02-types.md),
[syntax & stdlib](03-syntax-stdlib.md), [patterns](04-patterns-data.md), [async](05-coroutines-task-errors.md),
[performance](06-performance-memory.md).

## Identity
- Luau = Lua 5.1 core + gradual types + modern syntax + sandboxing + fast VM (optional native codegen). Roblox runs
  Luau inside the Engine; the standalone `luau` CLI has **no** `game`, `Instance`, `task`, `workspace`.
- Not available in Roblox: `io`, `os.execute`, `os.remove`, `require` of files on disk, `package`, `debug.sethook`,
  `load`/`dofile`, C modules, `goto`, integer subtype (`5 // 2` is float division floored, `math.type` absent),
  `<const>`/`<close>` Lua 5.4 attributes, `utf8` 5.3 extras beyond Luau's `utf8` library.
- `loadstring` exists on the server only when `ServerScriptService.LoadStringEnabled` is on; it de-optimizes the
  environment. Treat as never.
- Globals `getfenv`/`setfenv` exist but disable optimizations (imports, fastcalls) for the whole script. Never use.

## Values
| Fact | Consequence |
|---|---|
| Only `nil` and `false` are falsy | `0`, `""`, `{}` are truthy. `x or default` breaks when `false` is valid → use `if x == nil then default else x`. |
| One number type: IEEE-754 double | Integers exact to 2^53. Money/ids above that lose precision; store large ids as strings. `0.1 + 0.2 ~= 0.3`. |
| `NaN ~= NaN` | `n ~= n` detects NaN. `math.isnan/isinf/isfinite` exist (Luau 2025+, Roblox docs list them). |
| Strings are immutable byte arrays | `#s` is bytes, not characters. Use `utf8.len`, `utf8.codes` for text. |
| Tables are references | Assignment/argument passing aliases. Remotes and DataStores **copy** (and strip metatables). |
| `vector` is a native value type | Roblox `Vector3` is backed by it; `vector.create(x,y,z)` works in Roblox and CLI. |
| `buffer` is a fixed-size mutable byte block | Use for binary serialization; replicates through remotes. |

## Tables
- Hybrid array/hash. `#t` is defined only for sequences (no holes). Sparse arrays → keep an explicit count.
- Array index starts at 1. `t[#t + 1] = v` or `table.insert(t, v)`; pre-size with `table.create(n)`.
- Removing while iterating forward shifts indices → iterate backwards or build a new table.
- `pairs` / generalized `for k, v in t` order is unspecified. Sort keys when output must be deterministic
  (serialization, seeds, tests, network hashes).
- `table.clone` is **shallow**; `table.freeze` is **shallow** and makes writes throw. Deep-freeze config explicitly.
- Mixed tables (array + string keys) do not survive remotes reliably; send pure arrays or pure dictionaries.
- Keys that are Instances/tables are fine in memory, become **strings** when sent over remotes.

## Functions, varargs, multiple returns
```luau
local function f(...: number?): (number, number)
	local n = select("#", ...)       -- counts trailing nils; #{...} does not
	local packed = table.pack(...)    -- packed.n holds the true count
	return n, packed.n
end
local a, b = f(1, nil, nil)          -- 3, 3
local t = { f(1) }                    -- only the LAST call in a list expands to multiple values
```
- `(f())` truncates to one value. `return f()` is a tail call (no stack growth).
- Closures capture variables, not values: loops create a fresh binding per iteration (safe to capture `i`).

## Operators and syntax that differ from other languages
- `~=` not-equal; `..` concat (numbers auto-convert; use string interpolation instead); `//` floor division
  (rounds toward −∞: `-7 // 2 == -4`); `%` result has the sign of the divisor.
- Compound assignment `+= -= *= /= //= %= ^= ..=` are statements, not expressions.
- `if c then a else b` is an **expression** (safe with `false`/`nil`); `c and a or b` fails when `a` is falsy.
- `continue` exists (contextual keyword). No `++`, no `!=`, no `&&`, no `?.` optional chaining, no `??`.
- String interpolation: `` `HP {hp}/{max}` `` (calls `tostring`; cannot contain a double brace `{{`).

## Scope and globals
- Always `local`. Assigning an undeclared name creates a global (typechecker warns). `_G` is per-VM and not
  replicated; `shared` likewise. Neither crosses client/server. Never use them for cross-script state — use
  ModuleScripts.
- A ModuleScript runs **once per VM** (server has one; each client has one). Its return value is cached and shared
  by all requirers on that side. Top-level module state is effectively a singleton per side.

## Errors (details: [05](05-coroutines-task-errors.md))
- `error(value, level)` throws any value (string, table). `pcall(f, ...)` → `ok, resultOrErr`. `xpcall(f, handler)`
  gets a traceback via `debug.traceback()` inside the handler.
- `pcall` does not roll back side effects. Validate → reserve → commit → present; see [security](../roblox/04-security.md).
- `assert(v, msg)` returns `v` and refines types. Use for programmer errors, not for untrusted input (return a
  result instead, so exploiters cannot spam error logs).

## Lua-5.x / other-language habits to drop
| Habit | Luau reality |
|---|---|
| `local x <const> = 1` (5.4) | `const x = 1` (Luau const binding; binding only, value still mutable) |
| `goto continue` | `continue` |
| `table.unpack` vs `unpack` | both exist; prefer `table.unpack` |
| `math.pow` | removed in 5.3+, exists in Luau but use `^` |
| `string.format("%s", nil)` | **errors** in Luau ("string expected, got nil") → wrap with `tostring(x)` or use interpolation |
| `string.format("%d", 3.7)` | truncates to `3` (no rounding) → `math.round` first if you mean rounding |
| JS `array.length`, `.push`, `.map` | `#t`, `table.insert`, explicit loops |
| Python `None`/`is None` | `nil`, `== nil` |

Verify: `luau` CLI for pure logic; Roblox-specific code needs luau-lsp with Roblox definitions and Studio.
Sources: luau:getting-started/syntax, luau:reference/library, luau:getting-started/compatibility, luau:guides/performance,
cd:luau/numbers, cd:luau/tables, cd:reference/engine/globals/LuaGlobals.
