--!strict
-- Client side of NetExample: sends camera pitch only when it changed noticeably, capped at 15 Hz.
-- Status: TYPECHECKED. Not run in Studio.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local NetClient = require(ReplicatedStorage.Net.NetClient)

local sendPitch = NetClient.sender("AimPitch", { capacity = 3, rate = 15 })
local lastSent = math.huge

RunService.PreRender:Connect(function()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local look = camera.CFrame.LookVector
	local pitch = math.deg(math.asin(math.clamp(look.Y, -1, 1)))
	if math.abs(pitch - lastSent) >= 1 and sendPitch(pitch) then -- send on change, not every frame
		lastSent = pitch
	end
end)

local page = NetClient.request("GetShopPage", 5, 1)
print("shop page 1:", page) -- nil means rejected or timed out: show a retry button, never hang the UI
