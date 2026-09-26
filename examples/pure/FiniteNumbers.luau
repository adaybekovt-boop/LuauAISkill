--!strict
-- Original reference example. NOT executed in Roblox Studio during pack creation.
-- Host: pure Luau
-- Finite and bounded numeric validation; no dependencies.
local FiniteNumbers = {}
function FiniteNumbers.is(value: unknown): boolean
    -- Portable baseline. Current Luau also documents math.isfinite(number).
    return type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end
function FiniteNumbers.inRange(value: unknown, minimum: number, maximum: number): number?
    assert(FiniteNumbers.is(minimum) and FiniteNumbers.is(maximum) and minimum <= maximum, "Invalid bounds")
    if type(value) ~= "number" or not FiniteNumbers.is(value) then
        return nil
    end
    if value < minimum or value > maximum then
        return nil
    end
    return value
end
function FiniteNumbers.integer(value: unknown, minimum: number, maximum: number): number?
    local n = FiniteNumbers.inRange(value, minimum, maximum)
    if n == nil or n % 1 ~= 0 then
        return nil
    end
    return n
end
return table.freeze(FiniteNumbers)
