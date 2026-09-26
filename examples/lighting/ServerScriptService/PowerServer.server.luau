--!strict
-- Building power state for everyone: Workspace attribute PowerState = "Normal" | "Emergency" | "Blackout".
-- Clients switch lights and presets locally (EmergencyLights / LightingController). Game logic (a generator puzzle,
-- a round event) calls setPower; a demo cycle runs when Workspace attribute PowerDemo is true.
-- Status: TYPECHECKED. Not run in Studio.
local Workspace = game:GetService("Workspace")

type PowerState = "Normal" | "Emergency" | "Blackout"

local function setPower(state: PowerState)
	Workspace:SetAttribute("PowerState", state)
end

setPower("Normal")

if Workspace:GetAttribute("PowerDemo") == true then
	while true do
		task.wait(20)
		setPower("Emergency")
		task.wait(15)
		setPower("Blackout")
		task.wait(8)
		setPower("Normal")
	end
end
