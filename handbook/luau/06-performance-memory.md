# Luau performance and memory

## TL;DR
- Measure before optimizing and keep a baseline.
- Reduce repeated work and allocations before changing architecture.
- Choose data layout for the actual access pattern.
- Use Actors only for separable work with a measured benefit.
- Track retained resources as well as allocation rate.

Read when: a profile shows Luau time (not rendering/physics) is the bottleneck, or memory grows.
Engine-level performance (rendering, physics, network, MicroProfiler): [roblox/08-performance](../roblox/08-performance.md).

## Order of work
1. Measure (MicroProfiler / Script Profiler / Luau heap). 2. Remove work (don't run it, run it less often, run
it for fewer objects). 3. Only then micro-optimize the remaining hot path. 4. Measure again.
Micro-optimizations below matter only in code that runs thousands of times per frame.

## What Luau already makes fast (don't hand-optimize)
- Global/library access (`math.floor`, `Vector3.new`) is imported at load time — `local floor = math.floor` is
  unnecessary unless `getfenv/setfenv/loadstring` de-optimized the script.
- `for k, v in t`, `pairs`, `ipairs` are equally fast; generalized iteration is recommended.
- `#t` is ~O(1) (cached). `table.insert(t, v)` is the fastest append when size is unknown.
- Method calls `obj:Method()` use fast paths; builtins (`math.*`, `bit32.*`, `vector.*`, `buffer.*`, `type`,
  `typeof`, `select("#")`) are "fastcalls".
- Closures that capture nothing mutable may be cached by the compiler (no allocation per call).
- Local functions can be inlined at `-O2` (Roblox compiles with optimizations).

## What costs real time
| Cost | Why | Fix |
|---|---|---|
| Allocation in hot loops (tables, closures, strings, `Vector3`?) | GC work; `Vector3` is a value type (cheap), tables/closures/strings are heap | reuse tables (`table.clear`), hoist closures, build strings once |
| Crossing into the engine (property get/set, method calls on Instances) | each call marshals through the reflection layer | cache Instance references and read values once per frame; batch writes |
| `Instance:GetDescendants()`/`GetChildren()` every frame | allocates big arrays | build registries from `ChildAdded`/tags once |
| `FindFirstChild` chains every frame | string compare per child | cache references on spawn |
| String concatenation in loops | O(n²) copying | `table.concat`, `buffer` |
| `pcall` in hot loops | cheap but not free; hides errors | validate once outside the loop |
| Metamethod-heavy OOP in inner loops | `__index` chain lookups | plain arrays of numbers (SoA) for 1000s of entities |
| `getfenv`/`setfenv`/`loadstring` | disables imports & fastcalls for the script | remove |
| Deep `__index` inheritance | per-access chain walk | flatten methods onto the class table |

## Data layout for many entities
```luau
--!strict
-- Struct-of-arrays: 5,000 particles updated per frame without per-entity tables or closures.
local N = 5000
local px = table.create(N, 0)
local vx = table.create(N, 0)
local alive = table.create(N, false)
local function step(dt: number)
	for i = 1, N do
		if alive[i] then
			px[i] += vx[i] * dt
		end
	end
end
step(1 / 60)
```
For byte-level compactness (terrain maps, pathfinding grids, network packets) use `buffer`.

## Native code generation (server scripts)
- `--!native` at top of a server Script/ModuleScript or `@native` on specific functions compiles to machine code.
  Helps numeric/table/buffer-heavy code; does little for code dominated by engine API calls.
- Annotate parameters (`v: Vector3`, `b: buffer`) — native code specializes on annotations.
- Limits: total native code size per game; functions > 64K instructions per block, > 32K blocks, 1M instructions
  per module fail to compile. Don't put `--!native` everywhere (startup time + memory).
- Breakpoints disable native execution of that function. `debug.dumpcodesize()` (command bar, Server view) shows
  sizes. Script Profiler marks native functions.

## Parallel Luau (Actors) — when CPU work is separable
See [roblox/08-performance](../roblox/08-performance.md#parallel-luau). Rule: only when profiling shows a large,
independent CPU workload (pathfinding grids, procedural generation, many raycasts). Parallel code cannot write most
Instance properties (thread safety `Unsafe`/`ReadSafe` in `python tools/api.py`); do the math in parallel, commit
results after `task.synchronize()`.

## Memory
- GC is incremental; there is no manual free. Memory "leaks" in Luau are **reachable** objects: tables in
  module-level registries, closures captured by live connections, Instances referenced after `Destroy()`.
- `Instance:Destroy()` locks the parent, disconnects the Instance's own connections and descendants; it does not
  clear your Lua references. Set registry entries to `nil` on `Destroying`/`PlayerRemoving`.
- Per-player tables keyed by `Player` must be cleared on `Players.PlayerRemoving`.
- Weak tables (`__mode = "k"`) help caches, not connection leaks.
- Tag memory: `debug.setmemorycategory("NPC")` inside a script to attribute its allocations in the Developer
  Console memory view; `debug.resetmemorycategory()`.
- Studio: Luau heap profiler (snapshots, compare) — find which script/table grows.

## Measuring in code
```luau
--!strict
local function timeIt(label: string, iterations: number, fn: () -> ())
	debug.profilebegin(label)              -- shows as a labeled block in MicroProfiler
	local t0 = os.clock()
	for _ = 1, iterations do fn() end
	local elapsed = os.clock() - t0
	debug.profileend()
	print(string.format("%s: %.3f us/iter", label, elapsed / iterations * 1e6))
end
timeIt("noop", 1000, function() end)
```
Never leave per-frame `print` in production (Output/console spam is expensive). Keep `profilebegin/end` balanced
(an error between them corrupts the stack — wrap or keep code between them non-throwing).

Sources: luau:guides/performance, luau:guides/profile, cd:luau/native-code-gen, cd:scripting/multithreading,
cd:studio/optimization/memory-usage, cd:studio/optimization/scriptprofiler.

## Separating native and engine costs
Native compilation accelerates eligible Luau instructions, not engine rendering,
physics, or the engine implementation behind an API call. Measure the relevant
subsystem before adding native annotations; a rendering bottleneck needs a rendering
change rather than a claim that native compilation will improve it.
