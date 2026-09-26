--!strict
-- Original reference example. NOT executed in Roblox Studio during pack creation.
-- Host: pure Luau
-- Frame-rate-aware scalar damping; presentation only, not authoritative simulation.
local ExponentialDamp = {}
function ExponentialDamp.step(current: number, target: number, response: number, dt: number): number
    assert(current == current and math.abs(current) < math.huge, "current must be finite")
    assert(target == target and math.abs(target) < math.huge, "target must be finite")
    assert(response >= 0 and response < math.huge and dt >= 0 and dt < math.huge, "Invalid response or dt")
    local alpha = 1 - math.exp(-response * dt)
    -- Convex form avoids overflow in target-current for opposite large finite values.
    return current * (1 - alpha) + target * alpha
end
return table.freeze(ExponentialDamp)
