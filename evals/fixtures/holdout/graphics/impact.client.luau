local template = game.ReplicatedStorage.ImpactAttachment
local function hit(part)
    template.Parent = part
    template.ParticleEmitter:Emit(12)
    task.delay(1, function() template:Destroy() end)
end
return hit
