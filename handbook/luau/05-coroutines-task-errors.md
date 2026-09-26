# Threads, scheduling, events and errors in Roblox Luau

Read when: anything asynchronous — yields, remotes, DataStores, timers, cleanup, "works once then breaks".
Related: [lifecycle](../roblox/02-lifecycle-events.md), [performance](06-performance-memory.md).

## Mental model
- One Luau VM per side (server, each client) plus Actors for parallel Luau. Code runs in coroutines ("threads")
  resumed by the task scheduler at **resumption points** each frame: input, `PreRender`, `PreAnimation`,
  `PreSimulation`, `PostSimulation`, task resumption, `Heartbeat`, `BindToClose`.
- Nothing runs concurrently inside one VM. A thread keeps running until it yields (`task.wait`, `WaitForChild`,
  `*Async` calls, `:Wait()`, `InvokeServer`, etc.). Between two statements without a yield, no other script can
  change state → "check then act" is atomic **only if there is no yield between check and act**.
- Every `*Async` / `Yields`-tagged API can take seconds, can fail, and lets other threads mutate state meanwhile.

## Choosing a scheduling primitive
| Intent | Use |
|---|---|
| Run a function that may yield without blocking the caller | `task.spawn(f, ...)` |
| Run after the current code finishes this cycle (avoid re-entrancy) | `task.defer(f, ...)` |
| Run once after N seconds, cancellable | `local th = task.delay(n, f)` … `task.cancel(th)` |
| Per-frame logic | `RunService.Heartbeat` (both), `PreSimulation` (before physics), `PreRender` (client, camera/visuals) |
| Fixed-rate deterministic simulation (server authority) | `RunService:BindToSimulation(fn, frequency)` ([05-server-authority](../roblox/05-server-authority.md)) |
| Wait for a single event | `signal:Wait()` or `signal:Once(fn)` |
| Wait for an Instance | `parent:WaitForChild(name, timeout)` → handle nil |
| Periodic low-rate work (every 0.5 s) | a single loop with `task.wait(0.5)` or accumulator on Heartbeat, not one thread per object |

Never busy-wait: `repeat task.wait() until flag` → use a signal/BindableEvent or `Once`.

## Events and connections
```luau
local Players = game:GetService("Players")
local conn = Players.PlayerAdded:Connect(function(player: Player) print(player.Name) end)
conn:Disconnect()                                    -- stops future calls AND drops queued deferred calls
Players.PlayerRemoving:Once(function(p: Player) print("first leave", p.Name) end)
```
- `SignalBehavior`: `Deferred` queues handlers to the next resumption point; `Default` still behaves as
  `Immediate` but Roblox says it will switch to Deferred; new templates and server-authority places use Deferred.
  **Write code that works under both**: never assume a handler already ran right after you trigger it, and never
  read "just-destroyed" state inside `Destroying`/`AncestryChanged` expecting the old hierarchy.
- Re-entrancy depth limit for events triggering events is 10.
- Destroying an Instance disconnects its signals. Connections to *other* objects (e.g. `Players.PlayerAdded` inside
  a per-character script) leak unless you disconnect them.
- Custom events: `BindableEvent` (Instance, crosses scripts on one side, copies tables like remotes) or a pure-Luau
  signal module (faster, keeps table identity). Don't use BindableFunction for control flow across unknown code
  (a yielding/erroring callee blocks or breaks the caller).

## Stale results and cancellation (the #1 async bug class)
```luau
--!strict
-- Generation token: ignore results that arrive after the owner changed state.
local generation = 0
local function loadPreview(itemId: string, fetch: (string) -> string, apply: (string) -> ())
	generation += 1
	local myGen = generation
	task.spawn(function()
		local ok, result = pcall(fetch, itemId)   -- may yield for a long time
		if myGen ~= generation then return end     -- a newer request superseded us
		if ok then apply(result) end
	end)
end
loadPreview("sword", function(id: string) return id .. ".png" end, print)
```
A token prevents stale commits; it does **not** undo side effects the operation already performed (a DataStore
write that timed out may still have succeeded).

## Errors
- `pcall(fn, a, b)` (no closure allocation) → `(true, ...)` or `(false, err)`. Wrap every `*Async` web call
  (DataStore, MessagingService, MemoryStore, HttpService, TeleportService, MarketplaceService info, TextService).
- `xpcall(fn, function(e) return debug.traceback(tostring(e), 2) end)` for logs with stack.
- Throw tables for structured errors: `error({ code = "NotEnoughCoins" }, 0)` and branch on `err.code`. Level `0`
  omits position prefix for string errors.
- A script error kills only that thread; connected handlers keep working. An error inside a `ModuleScript` at
  require time makes every `require` of it throw ("Requested module experienced an error while loading").
- Expected failures (invalid request, not enough currency) → return a result value, don't throw.

## Retry policy (web services)
```luau
--!strict
local function withRetry<T>(attempts: number, baseDelay: number, fn: () -> T): (boolean, T | string)
	local lastErr = "no attempts"
	for attempt = 1, attempts do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = tostring(result)
		if attempt < attempts then
			local backoff = math.min(30, baseDelay * 2 ^ (attempt - 1))
			task.wait(backoff * (0.5 + math.random() * 0.5)) -- jitter so servers don't retry in lockstep
		end
	end
	return false, lastErr
end
print(withRetry(3, 1, function() return 42 end))
```
Never retry validation errors or permission errors; retry only transient/throttle errors. For DataStores, retries
of writes to the same key must be **ordered per key** ([data](../roblox/06-data-persistence.md)).

## Coroutines directly
Use for generators/state machines you step manually. Rules: don't `coroutine.resume` threads created by the engine
or waiting on engine yields; `coroutine.wrap` rethrows errors; `coroutine.close(co)` to cancel a suspended one.
`task.spawn(co)` resumes a coroutine through the scheduler with error reporting.

## Timing gotchas
- `task.wait(0.1)` resumes on the next Heartbeat after ≥0.1 s → real interval ~0.1–0.13 s at 60 FPS. Accumulate
  `dt` for rate-exact logic.
- Server Heartbeat runs at up to 60 Hz; client frame rate varies (30–240+). Always multiply by `dt`; use
  exponential smoothing `alpha = 1 - math.exp(-rate * dt)` instead of fixed lerp factors.
- `os.clock()` for durations; `workspace:GetServerTimeNow()` for cross-machine timestamps (cooldowns shown on UI).

Sources: cd:scripting/scheduler, cd:scripting/events/deferred, cd:scripting/events/bindable, cd:reference/engine/libraries/task,
cd:reference/engine/classes/RunService, cd:cloud-services/data-stores/player-data-purchasing,
cd:performance-optimization/microprofiler/task-scheduler.
