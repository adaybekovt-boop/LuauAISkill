--!strict
-- Original reference example. NOT executed in Roblox Studio during pack creation.
-- Host: isolated target-compiler probe
-- @native requests code generation; acceptance is not evidence of a measured speedup.
@native
local function square(value: number): number
    return value * value
end
assert(square(5) == 25)
return true
