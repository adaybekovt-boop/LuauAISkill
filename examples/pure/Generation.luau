--!strict
-- Original reference example. NOT executed in Roblox Studio during pack creation.
-- Host: pure Luau
-- Invalidates late results. Does not cancel an already running external operation.
export type Guard = {
    next: () -> number,
    isCurrent: (token: number) -> boolean,
    invalidate: () -> (),
}
local Generation = {}
function Generation.new(): Guard
    local current = 0
    return {
        next = function(): number
            current += 1
            return current
        end,
        isCurrent = function(token: number): boolean
            return token == current
        end,
        invalidate = function(): ()
            current += 1
        end,
    }
end
return table.freeze(Generation)
