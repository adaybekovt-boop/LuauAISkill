--!strict
-- Shared interaction settings (client-visible: nothing secret here).
local Config = {
	TAG = "Interactable", -- CollectionService tag placed on Parts/Models in Studio
	DEFAULT_DISTANCE = 10, -- studs; per-object override: attribute Distance
	DISTANCE_SLACK = 4, -- server tolerance for latency/character size
	DEFAULT_COOLDOWN = 0.25, -- seconds per object; override: attribute Cooldown
	RATE = { capacity = 4, rate = 2 }, -- per-player interaction budget (burst, per second)
}
return table.freeze(Config)
