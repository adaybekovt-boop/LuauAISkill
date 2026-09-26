--!strict
-- Original reference example. NOT executed in Roblox Studio during pack creation.
-- Host: Roblox serial ModuleScript; choose one owner (server OR client)
-- Opt-in configuration using metadata checked at pinned docs SHA. Runtime not tested.
local Lighting = game:GetService("Lighting")
local LightingBaseline = {}
function LightingBaseline.apply(): ()
    -- Pinned 2026-09-25 YAML lists read/write None for these two members.
    -- Older versions/security contexts may differ: verify your actual host.
    -- Do not hide permission/rollout failures in an empty pcall.
    Lighting.LightingStyle = Enum.LightingStyle.Realistic
    Lighting.PrioritizeLightingQuality = true
    -- No Technology assignment; old protected property is superseded.
    -- Ambient, exposure, sky and light placement must be art-directed per scene.
end
return table.freeze(LightingBaseline)
