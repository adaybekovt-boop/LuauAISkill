# Luau types: strict, gradual, practical

Read when: designing module APIs, network contracts, data schemas, fixing type errors.
Related: [core](01-language-core.md), [patterns](04-patterns-data.md), [networking](../roblox/03-networking.md).

## Rules
- New files: `--!strict` on line 1. Legacy files: `--!nonstrict` then tighten per module. `--!nocheck` only for
  generated/vendored code.
- Types are **compile-time only**. `x :: T` is a cast, not a check. Remote/DataStore/HTTP/attribute input is
  `unknown` until refined with runtime checks (`typeof`, ranges, `math.isfinite`).
- Prefer `unknown` over `any` at trust boundaries. `any` silently disables checking everywhere it flows.
- Export types from the module that owns the data: `export type Item = {...}`; consumers use `Module.Item`.
- Never "fix" errors with blanket `:: any`. Refine, narrow, or add a small local interface type.

## Modes
| Directive | Meaning |
|---|---|
| `--!strict` | infer + report all type errors |
| `--!nonstrict` (default) | unannotated values are `any`; only obvious errors |
| `--!nocheck` | no type errors (lint still runs) |
| `--!native` | request native codegen for the script (performance, not typing) — see [06](06-performance-memory.md) |

Two solvers exist: the old one and the "new type solver" (luau-analyze 0.740 defaults to new). New-solver-only
features are marked **(NS)**; verify Studio's Script Analysis agrees before relying on them in a shared codebase.

## Syntax catalog
```luau
--!strict
type Vec = { x: number, y: number }                 -- table type (sealed when annotated)
type Id = string                                     -- alias (no nominal typing: Id == string)
type Maybe<T> = T?                                   -- optional = T | nil
type Dict<K, V> = { [K]: V }                         -- indexer
type Arr<T> = { T }                                  -- array shorthand for { [number]: T }
type Fn = (dt: number, ...Instance) -> (boolean, string?)   -- function type, variadic param, multiple returns
type Handler<A...> = (A...) -> ()                    -- generic type pack
type Result<T, E = string> =                        -- generic default
	{ ok: true, value: T } | { ok: false, err: E }   -- discriminated union on a singleton field
type Mode = "idle" | "chase" | "attack"              -- string singletons (enums without Enum)
type HasHealth = { health: number }
type HasTeam = { team: string }
type Both = HasHealth & HasTeam                      -- intersection (merge shapes / overloads)
```
New-solver-only syntax:
```luau
-- NS (new type solver only)
type ReadOnlyPoint = { read x: number, read y: number }   -- read-only property
local k: keyof<{ a: number, b: string }> = "a"            -- builtin type function
```

Type packs like `(number, string)` exist only inside function types/generics, never as a standalone value type.

## Inference and refinement
- Locals infer from initializers; empty table literals stay unsealed within scope. Annotate parameters and return
  types of every exported function — inference of callers is then stable.
- Refinements: truthiness (`if x then`), `type(x) == "number"`, `typeof(x) == "Instance"`, `x:IsA("BasePart")`,
  equality with singletons (`if s.kind == "rect"`), `assert(...)`, early `return`.
- Exhaustiveness: in the final `else`, pass the value to `local function absurd(x: never) end` — adding a union
  member without handling it becomes a type error.
- `typeof(expr)` in a type position captures the inferred type: `type Config = typeof(DEFAULT_CONFIG)`.

## Instances and Roblox types
- `Instance.new("Part")` returns `Part`. `FindFirstChild` returns `Instance?`; refine with `:IsA` before property
  access. `WaitForChild` returns `Instance` (no nil) but may yield forever — pass a timeout and check nil.
- `workspace.Map.Door` is typed `any`/error under strict unless a sourcemap (Rojo/luau-lsp) tells the checker the
  DataModel shape. Prefer typed lookups: `local door = map:FindFirstChild("Door") :: Model?` only after you know the
  class, or refine with `IsA`.
- `script.Parent` is `Instance?`. Enum types are `Enum.Material` etc. (value type) — compare with `==`.

## Module boundaries
```luau
--!strict
-- Inventory.luau (server)
export type ItemId = string
export type Stack = { id: ItemId, count: number }
export type Inventory = { stacks: { Stack }, capacity: number }

local Inventory = {}
function Inventory.new(capacity: number): Inventory
	return { stacks = {}, capacity = capacity }
end
function Inventory.count(inv: Inventory, id: ItemId): number
	local n = 0
	for _, s in inv.stacks do
		if s.id == id then n += s.count end
	end
	return n
end
return Inventory
```
Cyclic requires between typed modules break inference (and runtime). Break cycles with a third "types" module or
dependency injection.

## Metatable "classes"
```luau
--!strict
local Account = {}
Account.__index = Account
type AccountData = { name: string, balance: number }
export type Account = typeof(setmetatable({} :: AccountData, Account))
-- (NS) alternative: export type Account = setmetatable<AccountData, typeof(Account)>

function Account.new(name: string, balance: number): Account
	return setmetatable({ name = name, balance = balance }, Account)
end
function Account.deposit(self: Account, amount: number) -- explicit self annotation is required today
	self.balance += amount
end
return Account
```
Callers still use `acc:deposit(5)`. Prefer plain functions over records when you do not need polymorphism.

## Runtime validation of `unknown` (trust boundary)
```luau
--!strict
local function readCount(v: unknown, max: number): number?
	if typeof(v) ~= "number" then return nil end
	if v ~= v or v % 1 ~= 0 or v < 1 or v > max then return nil end -- NaN, fractional, range
	return v
end
local function readVector(v: unknown, maxMagnitude: number): Vector3?
	if typeof(v) ~= "Vector3" then return nil end
	if v.X ~= v.X or v.Y ~= v.Y or v.Z ~= v.Z then return nil end    -- NaN components
	if v.Magnitude > maxMagnitude then return nil end                -- also rejects ±inf
	return v
end
```
`typeof` (Roblox) knows Roblox types (`"Vector3"`, `"Instance"`, `"EnumItem"`, `"buffer"`); `type` returns
`"userdata"` for them.

## Type functions (NS)
`type function` runs at analysis time using the `types` library to compute types (e.g. derive a readonly version of
a record). Useful for library authors; rarely worth it in game code. It never validates runtime data.

## Common errors → fixes
| Error | Fix |
|---|---|
| "Type 'Instance' could not be converted into 'Part'" | `if inst:IsA("Part") then ... end` |
| "Value of type 'T?' could be nil" | early return / `assert` / default with `if x == nil` |
| "Key 'Foo' not found in table" on a module | the module didn't export it, or the table was sealed; add the field to the type |
| Unknown global in strict | missing `local`, or a Roblox global unavailable in this context |
| Self type mismatch in OOP | annotate `self: ClassType` as above |
| Recursive type too complex | split into named aliases; avoid deep intersections |

Verify: `luau-analyze --mode=strict file.luau` (pure) or `luau-lsp analyze --definitions=@roblox=<globalTypes.None.d.luau>`
with a sourcemap (Roblox). See [tooling](../roblox/23-tooling-testing.md).
Sources: luau:types/overview, luau:types/basic-types, luau:types/tables, luau:types/generics, luau:types/refinements,
luau:types/unions-and-intersections, luau:types/object-oriented-programs, luau:types/type-functions,
luau:types/roblox-types, cd:luau/type-checking.
