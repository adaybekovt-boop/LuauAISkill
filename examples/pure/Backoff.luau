--!strict
-- Original reference example. NOT executed in Roblox Studio during pack creation.
-- Host: pure Luau
-- Delay calculation only. Does not make side-effecting operations safe to retry.
local Backoff = {}
local function finite(n: number): boolean
    return n == n and n > -math.huge and n < math.huge
end
function Backoff.delay(attempt: number, base: number, cap: number, uniform: number): number
    assert(finite(attempt) and attempt >= 1 and attempt % 1 == 0, "Positive attempt required")
    assert(finite(base) and finite(cap) and base > 0 and cap >= base, "Invalid delay bounds")
    assert(finite(uniform) and uniform >= 0 and uniform <= 1, "uniform must be in [0,1]")
    local exponent = math.min(attempt - 1, 52)
    local ceiling = math.min(cap, base * (2 ^ exponent))
    return uniform * ceiling -- full jitter; bounded by cap
end
return table.freeze(Backoff)
