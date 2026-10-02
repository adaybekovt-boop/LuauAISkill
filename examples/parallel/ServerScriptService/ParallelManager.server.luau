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
