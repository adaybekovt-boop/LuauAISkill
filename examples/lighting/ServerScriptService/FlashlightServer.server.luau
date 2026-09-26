--!strict
-- Flashlight state for other players' views: the server stores FlashlightOn and FlashPitch (quantized) as
-- character attributes. Clients render the lights themselves. Rate-limited; pitch is cosmetic but still validated.
-- Status: TYPECHECKED. Not run in Studio.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TokenBucket = require(ReplicatedStorage.Lib.TokenBucket)
local Validate = require(ReplicatedStorage.Lib.Validate)

local folder = Instance.new("Folder")
folder.Name = "FlashlightRemotes"
local toggle = Instance.new("RemoteEvent")
toggle.Name = "Toggle"
toggle.Parent = folder
local pitch = Instance.new("UnreliableRemoteEvent")
pitch.Name = "Pitch"
pitch.Parent = folder
folder.Parent = ReplicatedStorage

local limiter = TokenBucket.new({ Toggle = { capacity = 4, rate = 2 }, Pitch = { capacity = 8, rate = 6 } })

toggle.OnServerEvent:Connect(function(player: Player, on: unknown)
	local value = Validate.boolean(on)
	local character = player.Character
	if value == nil or not character or not limiter:allow(player, "Toggle", os.clock()) then
		return
	end
	character:SetAttribute("FlashlightOn", value)
end)

pitch.OnServerEvent:Connect(function(player: Player, degrees: unknown)
	local value = Validate.number(degrees, -80, 80)
	local character = player.Character
	if value == nil or not character or not limiter:allow(player, "Pitch", os.clock()) then
		return
	end
	character:SetAttribute("FlashPitch", math.round(value / 2) * 2) -- 2° steps: invisible, fewer changes
end)

Players.PlayerRemoving:Connect(function(player: Player)
	limiter:forget(player)
end)
