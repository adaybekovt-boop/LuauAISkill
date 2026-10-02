# Code quality rules for AI-written Roblox code

## TL;DR
- Write strict, explicit code with bounded failure paths.
- Keep naming, ownership, and module boundaries consistent.
- Centralize cleanup for every owned resource.
- Review security and lifecycle behavior before polishing style.
- Report only verification that actually ran.

Read when: writing or reviewing any code. These are defaults; follow the project's existing conventions first.

## Rules
1. **Match the project.** Inspect existing structure, naming, frameworks, formatter (StyLua), linter (Selene), typing
   mode before writing. Don't introduce a framework or re-architecture unless asked.
2. **Explicit boundaries.** Every file is clearly server, client, or shared (by location and a header comment if
   ambiguous). Shared modules never touch server-only services or `Players.LocalPlayer`.
3. **Typed public interfaces.** `--!strict`; annotate exported function params/returns; export types for data
   crossing modules. `unknown` at trust boundaries.
4. **Services via `game:GetService`** at the top of the file, named exactly as the service (`local Players =
   game:GetService("Players")`). Use `workspace`/`Workspace` consistently.
5. **No arbitrary waits.** No `task.wait(1)` "to let things load". Wait on events/conditions (`WaitForChild` with
   timeout, `Loaded`, signals).
6. **No polling where an event exists** (`Changed`, `GetPropertyChangedSignal`, `AttributeChanged`, tags).
7. **Deterministic cleanup** for every connection, instance, thread, tween (see below).
8. **Small functions, clear names** (`applyDamage`, `canInteract`), constants in UPPER_SNAKE or a config module; no
   magic numbers scattered in handlers; no magic strings for remotes/tags/attributes — centralize names.
9. **No god modules** (> ~500–800 lines usually means split by responsibility).
10. **Errors are handled where they can be acted on**: pcall web calls; validate inputs; don't wrap everything in
    pcall to hide bugs.
11. **Comments explain why**, not what. Document invariants and security assumptions.
12. **No deprecated APIs in new code** (`python tools/api.py X.Y` shows status); no `wait/spawn/delay`.
13. **Honest reporting**: never claim code was run in Studio unless it was; say what was verified and how.

## Cleanup
### Module state and startup
Expose an explicit `start()` for modules that create connections, loops, or world state. Require-time side
effects make initialization order and isolated tests fragile; pure constant/configuration modules need no
startup phase. Own shared state in a ModuleScript with a small typed API, not `_G`: global mutation hides
ownership, readers can race initialization order, and a global key does not provide a checked module contract.

Ownership: whoever creates it destroys it. Patterns:
```luau
--!strict
-- Minimal cleanup bag (a fuller typed version lives in examples/lib/ReplicatedStorage/Lib/Cleanup.luau).
type Task = RBXScriptConnection | Instance | thread | () -> ()
local function newBag()
	local tasks: { Task } = {}
	local bag = {}
	function bag.add(t: Task)
		table.insert(tasks, t)
	end
	function bag.clean()
		for i = #tasks, 1, -1 do                 -- reverse order: undo in LIFO
			local t = tasks[i]
			tasks[i] = nil
			if typeof(t) == "RBXScriptConnection" then
				t:Disconnect()
			elseif typeof(t) == "Instance" then
				t:Destroy()
			elseif type(t) == "thread" then
				if coroutine.status(t) ~= "dead" then task.cancel(t) end
			elseif type(t) == "function" then
				t()
			end
		end
	end
	return bag
end
local bag = newBag()
bag.add(workspace.ChildAdded:Connect(function() end))
bag.clean()
```
Tie bags to lifetimes: per character (clean on `Destroying`/`CharacterRemoving`), per player (on
`PlayerRemoving`), per tagged object (binder removal), per UI screen (on close), per round (round end).

## Review checklist (use on your own output)
- [ ] Runs on the right side; no client authority over gameplay state.
- [ ] Every remote handler validates and rate-limits.
- [ ] No deprecated APIs; no invented APIs (checked with `tools/api.py` / `tools/check_api_refs.py`).
- [ ] Every `WaitForChild` has a timeout or is provably safe; streaming considered for Workspace lookups.
- [ ] Every connection/instance/thread has an owner and cleanup.
- [ ] No yields between check and commit in transactions.
- [ ] Web calls wrapped in pcall with bounded retries.
- [ ] Per-player tables cleared on leave.
- [ ] Per-frame work justified and bounded.
- [ ] Types: strict mode passes (or explained exceptions).
- [ ] Config/magic values centralized.

Sources: cd:scripting/locations, cd:scripting/services, cd:performance-optimization/improve,
cd:reference/engine/classes/Instance, luau:types/overview.
