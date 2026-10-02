# Parallel NPC planning behind an executable measurement gate

A serial-by-default nearest-target planner with Actor workers, immutable numeric snapshots, bounded jobs,
serial result application, output parity checks and captured end-to-end timing before enabling parallel work.

Evidence: **TYPECHECKED** (strict, old + new solver, pinned Roblox definitions); pure logic **CLI-EXECUTED**.
**Studio / live: NOT RUN.**

## Architecture
- One server manager snapshots at most 200 tagged NPCs and 32 living player targets every 0.2 seconds. The pure
  planner selects nearest horizontal candidates within 160 studs with a deterministic UserId tie-break.
- Four Actor workers receive plain numeric tables through SendMessage. Their parallel callback performs only pure
  Luau computation, then synchronizes before firing the serial reply event. No unsafe Instance mutation occurs in parallel.
- An epoch labels jobs. A 250 ms timeout discards late replies and falls back to serial. Output is sorted back into
  snapshot order before comparison/application; actor readiness has a separate bounded wait.
- Five warmups and 20 paired real-scene samples compare serial planning against full parallel dispatch/copy/
  scheduling/synchronize/merge latency on the same snapshot. Enable only with exact output parity, parallel p95
  below 85% of serial p95, and at least 0.2 ms absolute saving. Raw arrays and decision are printed as JSON.
- The gate resets when NPC/player counts change or after two minutes. A small nearest-target job will usually
  remain serial; passing synthetic gate unit tests is not a measured speedup.
- Applying a result only sets a candidate `TargetUserId` attribute. Your authoritative NPC manager rechecks life,
  distance, LOS, faction, path feasibility and current state before moving/damaging. No per-NPC loop is spawned.

## When NOT to use

do not parallelize before a profiler shows this planner is material. This simple workload may
be too small to benefit, which the gate is designed to establish. Actors don't make arbitrary Roblox APIs thread-safe;
pathfinding and instance mutation remain serial. It is not a full pathfinding or NPC movement replacement.

## Setup and integration
Copy `examples/parallel/ServerScriptService` into a test place. Tag NPC Models `ParallelNpc`, set their
PrimaryPart, and let an existing server NPC manager consume the candidate attribute. The standalone Worker script
is a inert template outside an Actor; the manager clones it under four Actors and waits for readiness.
Use representative NPC/target counts, target device and scene. Save PARALLEL_GATE output together with Studio build,
hardware, place revision and MicroProfiler capture. Re-run after changing the planner, target set, worker count or
architecture. No parallel speedup or latency result has been measured for this repository.

## Implementation

### `examples/parallel/ServerScriptService/Parallel/Planner.luau`

<!-- code: examples/parallel/ServerScriptService/Parallel/Planner.luau -->
```luau
-- file: examples/parallel/ServerScriptService/Parallel/Planner.luau
--!strict
export type Point = { id: number, x: number, z: number }
export type Choice = { npcId: number, targetId: number, distanceSquared: number }
local Planner = {}
function Planner.plan(npcs: { Point }, targets: { Point }): { Choice }
	local choices: { Choice } = {}
	for _, npc in npcs do
		local bestId, bestDistance = 0, 160 * 160
		for _, target in targets do
			local dx, dz = npc.x - target.x, npc.z - target.z
			local distance = dx * dx + dz * dz
			if distance < bestDistance or (distance == bestDistance and (bestId == 0 or target.id < bestId)) then
				bestDistance, bestId = distance, target.id
			end
		end
		table.insert(choices, { npcId = npc.id, targetId = bestId, distanceSquared = bestDistance })
	end
	return choices
end
function Planner.equal(a: { Choice }, b: { Choice }): boolean
	if #a ~= #b then return false end
	for i, choice in a do
		if choice.npcId ~= b[i].npcId or choice.targetId ~= b[i].targetId
			or choice.distanceSquared ~= b[i].distanceSquared then return false end
	end
	return true
end
function Planner.p95(samples: { number }): number
	assert(#samples > 0, "Samples required")
	local sorted = table.clone(samples); table.sort(sorted)
	return sorted[math.ceil(#sorted * 0.95)]
end
function Planner.gate(serial: { number }, parallel: { number }, parity: boolean): boolean
	-- Both a relative win and an absolute 0.2 ms saving, measured end-to-end.
	if not parity or #serial < 20 or #parallel < 20 then return false end
	local a, b = Planner.p95(serial), Planner.p95(parallel)
	return b < a * 0.85 and a - b > 0.0002
end
return Planner
```
<!-- /code -->

### `examples/parallel/ServerScriptService/Parallel/Worker.server.luau`

<!-- code: examples/parallel/ServerScriptService/Parallel/Worker.server.luau -->
```luau
-- file: examples/parallel/ServerScriptService/Parallel/Worker.server.luau
--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local Planner = require(ServerScriptService.Parallel.Planner)
local actor = script:GetActor()
if not actor then return end -- template lives outside an Actor and does no work
local reply = ServerScriptService:WaitForChild("PlannerReply") :: BindableEvent
local index = actor:GetAttribute("WorkerIndex") :: number
actor:BindToMessageParallel("Plan", function(epoch: number, npcs: { Planner.Point }, targets: { Planner.Point })
	local choices = Planner.plan(npcs, targets) -- pure data only, no Instance access or unsafe calls
	task.synchronize()
	reply:Fire(epoch, index, choices) -- serial phase; includes synchronization cost in end-to-end timing
end)
reply:Fire(0, index, {}) -- readiness after the handler is installed
```
<!-- /code -->

### `examples/parallel/ServerScriptService/ParallelManager.server.luau`

<!-- code: examples/parallel/ServerScriptService/ParallelManager.server.luau -->
```luau
-- file: examples/parallel/ServerScriptService/ParallelManager.server.luau
--!strict
-- Candidates only: an existing authoritative NPC manager consumes TargetUserId and verifies LOS/path/state.
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local Planner = require(script.Parent.Parallel.Planner)
local WORKERS, MAX_NPCS, MAX_TARGETS = 4, 200, 32
local reply = Instance.new("BindableEvent")
reply.Name = "PlannerReply"; reply.Parent = ServerScriptService
local actors: { Actor } = {}
local ready: { [number]: boolean } = {}
local epoch = 0
local results: { [number]: { Planner.Choice } } = {}
local replies = 0
local replyConnection = reply.Event:Connect(function(job: number, index: number, choices: { Planner.Choice })
	if job == 0 then ready[index] = true
	elseif job == epoch and not results[index] then results[index] = choices; replies += 1 end
end)
for i = 1, WORKERS do
	local actor = Instance.new("Actor")
	actor.Name = "PlannerWorker" .. i; actor:SetAttribute("WorkerIndex", i); actor.Parent = ServerScriptService
	local worker = script.Parent.Parallel.Worker:Clone()
	worker.Enabled = false; worker.Parent = actor; worker.Enabled = true
	table.insert(actors, actor)
end
local running = true
local function parallel(npcs: { Planner.Point }, targets: { Planner.Point }): { Planner.Choice }?
	epoch += 1; results = {}; replies = 0
	for index, actor in actors do
		local batch: { Planner.Point } = {}
		for i = index, #npcs, WORKERS do table.insert(batch, npcs[i]) end
		actor:SendMessage("Plan", epoch, batch, targets)
	end
	local deadline = os.clock() + 0.25
	while replies < WORKERS and running and os.clock() < deadline do task.wait() end
	if replies < WORKERS then epoch += 1; return nil end -- late messages are discarded
	local combined: { Planner.Choice } = {}
	for i = 1, WORKERS do for _, choice in results[i] do table.insert(combined, choice) end end
	table.sort(combined, function(a: Planner.Choice, b: Planner.Choice) return a.npcId < b.npcId end)
	return combined
end
local function snapshot(): ({ Planner.Point }, { Planner.Point }, { [number]: Model })
	local npcs: { Planner.Point } = {}
	local targets: { Planner.Point } = {}
	local models: { [number]: Model } = {}
	local tagged = CollectionService:GetTagged("ParallelNpc")
	for _, instance in tagged do
		if #npcs >= MAX_NPCS then break end
		if instance:IsA("Model") and instance.PrimaryPart then
			local id = #npcs + 1
			local primary = instance.PrimaryPart :: BasePart
			local p = primary.Position
			table.insert(npcs, { id = id, x = p.X, z = p.Z }); models[id] = instance
		end
	end
	local players = Players:GetPlayers()
	table.sort(players, function(a: Player, b: Player) return a.UserId < b.UserId end)
	for _, player in players do
		if #targets >= MAX_TARGETS then break end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
			table.insert(targets, { id = player.UserId, x = root.Position.X, z = root.Position.Z })
		end
	end
	return npcs, targets, models
end
local function cleanup()
	if not running then return end
	running = false; replyConnection:Disconnect()
	for _, actor in actors do actor:Destroy() end
	reply:Destroy()
end
script.Destroying:Connect(cleanup)
local deadline = os.clock() + 5
while running do
	local count = 0; for _ in ready do count += 1 end
	if count == WORKERS or os.clock() >= deadline then break end
	task.wait()
end
local readyCount = 0; for _ in ready do readyCount += 1 end
local useParallel = false
local serialSamples: { number } = {}
local parallelSamples: { number } = {}
local parity = true
local warmups = 0
local measuredNpcCount, measuredTargetCount = -1, -1
local gateExpires = 0
while running do
	local npcs, targets, models = snapshot()
	if #npcs ~= measuredNpcCount or #targets ~= measuredTargetCount or os.clock() >= gateExpires then
		measuredNpcCount, measuredTargetCount = #npcs, #targets
		serialSamples, parallelSamples = {}, {}
		warmups = 0; parity = true; useParallel = false; gateExpires = os.clock() + 120
	end
	local choices: { Planner.Choice }
	if readyCount == WORKERS and #npcs > 0 and #targets > 0 and #serialSamples < 20 then
		-- Same live snapshot for both paths, inclusive of messaging, scheduling, copying and merging.
		local t = os.clock(); local baseline = Planner.plan(npcs, targets); local serialTime = os.clock() - t
		t = os.clock(); local result = parallel(npcs, targets); local parallelTime = os.clock() - t
		if not running then break end
		parity = parity and result ~= nil and Planner.equal(baseline, result or {})
		warmups += 1
		if warmups > 5 then
			table.insert(serialSamples, serialTime); table.insert(parallelSamples, parallelTime)
		end
		choices = baseline
		if #serialSamples == 20 then
			useParallel = Planner.gate(serialSamples, parallelSamples, parity)
			print("PARALLEL_GATE " .. HttpService:JSONEncode({ serialSeconds = serialSamples,
				parallelSeconds = parallelSamples, parity = parity, enabled = useParallel,
				npcCount = #npcs, targetCount = #targets, workers = WORKERS,
				environment = "Record Studio build, device, scene and MicroProfiler capture alongside this receipt" }))
		end
	elseif useParallel then
		local result = parallel(npcs, targets)
		if not running then break end
		if result then choices = result else useParallel = false; choices = Planner.plan(npcs, targets) end
	else choices = Planner.plan(npcs, targets) end
	-- Snapshot may be stale by application time. Do not move or damage here.
	for _, choice in choices do
		local model = models[choice.npcId]
		if model and model.Parent then model:SetAttribute("TargetUserId", choice.targetId) end
	end
	task.wait(0.2)
end
```
<!-- /code -->

## How to test

| Scenario | Required observation |
|---|---|
| CLI tie/range / parity | Candidate choice deterministic and equal between merged serial-compatible outputs |
| Tiny workload | Gate remains serial unless the recorded requirements genuinely pass |
| Representative load | Retain 20 paired samples, p95 comparison, parity and profiler capture; never invent numbers |
| Worker missing / stalled / late | Ready/job deadlines prevent a stuck manager; stale epochs discarded; serial fallback |
| NPC destroyed / target leaves in flight | Application ignores destroyed models; consuming manager rejects stale target |
| Change load / wait two minutes | Gate clears and remeasures rather than extrapolating old samples |
| Destroy owner script | Worker Actors, connections and reply event are removed |

The unit test's artificial timing numbers exercise the gate decision only. They are explicitly not benchmark results.

## Failure paths and limits
The heartbeat-style scheduler includes task scheduling latency in parallel timings; optimizing that transport
would be a separate measured change. CollectionService iteration defines only this snapshot's NPC IDs; they are
not persistent entity IDs. Counts are hard caps, so establish LOD/selection priorities for larger populations in
the owning NPC manager. Current records report the measured workload and raw data but do not identify hardware
automatically; the operator must attach it. Snapshot construction is shared overhead; profile it separately.
If parallel processing stops helping, leave serial enabled rather than weakening the gate.

## Verification
From the skill directory, run `python tools/check_all.py`. Pure tests for this recipe:
`luau examples/tests/parallel.spec.luau`. The checker runs both Luau solvers. Engine coverage remains NOT RUN until you retain
assertion output from the specified Studio scenario with Studio build, place revision, peers, and device.

Sources: cd:reference/engine/classes/Actor, api:Actor.BindToMessageParallel, api:Actor.SendMessage, api:Instance.GetActor.
