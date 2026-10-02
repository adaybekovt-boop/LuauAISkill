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
