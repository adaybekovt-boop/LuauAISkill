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
