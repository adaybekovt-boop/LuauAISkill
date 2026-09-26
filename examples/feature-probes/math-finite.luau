--!strict
-- Original reference example. NOT executed in Roblox Studio during pack creation.
-- Host: isolated target-host probe
-- Current documented predicates; tests actual target availability.
assert(math.isfinite(42))
assert(not math.isfinite(math.huge))
assert(math.isnan(0 / 0))
assert(math.isinf(-math.huge))
return true
