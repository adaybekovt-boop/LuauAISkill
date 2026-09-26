--!strict
-- Original reference example. NOT executed in Roblox Studio during pack creation.
-- Host: isolated target-compiler probe
-- Tests explicit type arguments described by current Luau documentation.
local function identity<T>(value: T): T
    return value
end
local result = identity<<number>>(42)
assert(result == 42)
return true
