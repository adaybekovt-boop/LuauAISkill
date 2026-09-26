--!strict
-- Original reference example. NOT executed in Roblox Studio during pack creation.
-- Host: isolated target-compiler probe
-- Do not require from production bootstrap before target compiler accepts it.
const settings: {enabled: boolean} = {enabled = true}
settings.enabled = false -- binding is constant, value is still mutable
assert(settings.enabled == false)
return true
