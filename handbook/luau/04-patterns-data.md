# Luau patterns: modules, objects, data, iteration, cleanup

## TL;DR
- Choose the simplest data structure that represents the state.
- Give modules clear ownership and a small public surface.
- Keep persistent and replicated data serialization-friendly.
- Use metatables only when they simplify the design.
- Make cleanup and resource ownership explicit.

Read when: structuring code, choosing OOP vs plain data, designing serializable state.
Related: [types](02-types.md), [architecture](../roblox/21-architecture.md), [code quality](../roblox/22-code-quality.md).

## Choose the simplest shape
| Need | Use | Avoid |
|---|---|---|
| Stateless helpers | module table of functions | classes with no state |
| One instance per side (service) | module with local state + `init/start` | `_G`, globals |
| Many instances with behaviour | metatable class or closure object | deep inheritance chains |
| Data that is saved / sent over network | plain tables of primitives, arrays, dictionaries | metatables, functions, Instances, mixed tables |
| Variant data | discriminated union `{ kind: "..." }` | booleans explosion (`isA, isB, isC`) |
| Polymorphism | table of handlers keyed by kind | `if kind == ... elseif` in 12 places |

## Module patterns
```luau
--!strict
-- Plain module: private state is local, API is the returned table.
local Cooldowns = {}
local lastUse: { [Player]: { [string]: number } } = {}

function Cooldowns.ready(player: Player, action: string, seconds: number, now: number): boolean
	local byAction = lastUse[player]
	if byAction == nil then
		byAction = {}
		lastUse[player] = byAction
	end
	local last = byAction[action]
	if last ~= nil and now - last < seconds then
		return false
	end
	byAction[action] = now
	return true
end

function Cooldowns.forget(player: Player)
	lastUse[player] = nil -- call from Players.PlayerRemoving or this table leaks
end

return Cooldowns
```
- Never `require` inside hot functions (cached, but hides dependencies). Require at top.
- A module must not start loops, connect events, or mutate the world at require time unless it is an entrypoint.
  Expose `start()` so tests and bootstrap control order.

## Class pattern (typed)
```luau
--!strict
local Door = {}
Door.__index = Door

type DoorData = { model: Model, isOpen: boolean, connections: { RBXScriptConnection } }
export type Door = typeof(setmetatable({} :: DoorData, Door))

function Door.new(model: Model): Door
	local self = setmetatable({ model = model, isOpen = false, connections = {} }, Door)
	return self
end

function Door.setOpen(self: Door, open: boolean)
	if self.isOpen == open then return end
	self.isOpen = open
	self.model:SetAttribute("Open", open)
end

function Door.destroy(self: Door)
	for _, c in self.connections do
		c:Disconnect()
	end
	table.clear(self.connections)
end

return Door
```
Inheritance: set the subclass metatable `__index` to the base; keep hierarchies ≤ 2 levels. Prefer composition
(object holds components) over inheritance.

## Closure objects (no metatables, fully private)
```luau
--!strict
export type Counter = { increment: () -> number, get: () -> number }
local function newCounter(start: number): Counter
	local value = start
	return {
		increment = function(): number
			value += 1
			return value
		end,
		get = function(): number
			return value
		end,
	}
end
local c = newCounter(0)
c.increment()
print(c.get())
```
Costs one closure per method per instance; fine for tens/hundreds of objects, not for 10k particles.

## Immutable-style data
- Treat config as read-only: `return table.freeze({ ... })` at module end; nested tables need their own freeze.
- Update state by returning a new table when snapshots/undo/diffing matter; mutate in place in hot paths.
- `table.clone` for shallow copies; write an explicit `deepCopy` for known-depth data (no cycles, no Instances).

```luau
--!strict
local function deepFreeze<T>(t: T): T
	if type(t) == "table" and not table.isfrozen(t) then
		for _, v in t :: any do
			deepFreeze(v)
		end
		table.freeze(t :: any)
	end
	return t
end
local CONFIG = deepFreeze({ sprint = { speed = 24, drain = 12 }, walk = { speed = 16 } })
print(CONFIG.sprint.speed)
```

## Serialization-friendly structures (DataStore, remotes, MemoryStore)
- Keys: strings or dense 1..n arrays. No mixed tables, no holes (`nil` inside arrays truncates), no NaN/inf.
- Values: string, number, boolean, nested tables of those. Encode Vector3/CFrame/Color3 as arrays of numbers.
  Remotes do carry Roblox types (Vector3, CFrame, Instance refs, buffer); DataStores store JSON: nil, boolean,
  finite numbers, strings, tables of those, and `buffer` — nothing else (Vector3 etc. silently become nil or error).
  Numeric keys become strings when the table has no array part.
- Include `schemaVersion` in every persisted root. Store ids (`itemId`), never display names or Instance paths.
- Sizes: DataStore value ≤ 4 MB per key (JSON-encoded length); keep player profiles far below (tens of KB).

## Iterators
For a leaderboard or top-N view of a dictionary, first build a dense array of records containing the key/name
and score. Sort with a strict comparator: a greater score ranks first, and equal scores use the name as a
deterministic tie-breaker. Never use a non-strict comparison for ties. Iterate only through the smaller of the
requested count and the array length, so a short leaderboard does not index missing records.

```luau
--!strict
-- Custom stateless iterator over every n-th element.
local function every<T>(t: { T }, n: number): () -> (number?, T?)
	local i = 0
	return function()
		i += n
		if i <= #t then
			return i, t[i]
		end
		return nil, nil
	end
end
for i, v in every({ 10, 20, 30, 40 }, 2) do
	print(i, v)
end
```
Generalized iteration also calls `__iter` metamethods — use it for custom collections.

## Metatables and metamethods worth knowing
`__index` (fallback lookup / methods), `__newindex` (intercept writes — proxies, read-only views), `__call`,
`__eq`/`__lt`/`__le`, `__tostring`, `__len`, `__iter`, `__mode` (`"k"`, `"v"`, `"kv"` weak tables), `__metatable`
(lock). Arithmetic: `__add __sub __mul __div __idiv __mod __pow __unm __concat`. Metamethods run on every access —
never do I/O or yields in them.

## Weak tables
Cache keyed by object without preventing GC: `setmetatable({}, { __mode = "k" })`. Instances referenced elsewhere
(parented, in other tables, captured by connections) are not collected — weak tables do not fix leaks caused by
live connections. Destroyed Instances still referenced by Lua remain as memory until references drop.

## Cleanup / ownership pattern (lifecycle)
Every object that connects events, creates Instances, or schedules threads owns a cleanup list and a `destroy`.
See `examples/lib/ReplicatedStorage/Lib/Cleanup.luau` (typed, re-entrancy-safe) and
[code quality](../roblox/22-code-quality.md#cleanup).

Pitfalls
- Default table shared across instances: `function new(opts) opts = opts or DEFAULT` then mutating `opts` mutates
  `DEFAULT`. Clone.
- `table.insert(t, pos, v)` with `pos` > `#t + 1` errors.
- Removing from `CollectionService` lists while iterating the same list — collect first.

Sources: luau:types/object-oriented-programs, luau:reference/library, cd:luau/metatables, cd:luau/tables,
cd:cloud-services/data-stores/best-practices, cd:scripting/events/remote.
