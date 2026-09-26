--!strict
-- Entry point for the combat example: starts the weapon modules and owns character lifecycle
-- (ragdoll on death, spawn protection) and cleanup. Clients send intent only; see Combat/*.
-- Status: TYPECHECKED. Not run in Studio.
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Combat = ServerScriptService.Combat
local Common = require(Combat.Common)
local Damage = require(Combat.Damage)
local Ragdoll = require(Combat.Ragdoll)
local Melee = require(Combat.Melee)
local Hitscan = require(Combat.Hitscan)
local Projectiles = require(Combat.Projectiles)

Melee.start()
Hitscan.start()
Projectiles.start()

local SPAWN_PROTECTION = 3

local function onCharacter(character: Model)
	Ragdoll.prepare(character)
	character:SetAttribute("InvulnerableUntil", os.clock() + SPAWN_PROTECTION) -- read by Damage (server clock)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.Died:Once(function()
			Ragdoll.enable(character)
		end)
	end
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end
Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	onPlayer(player)
end

Players.PlayerRemoving:Connect(function(player: Player)
	Common.forget(player)
	Projectiles.forget(player)
end)

Damage.killed:connect(function(victim: Humanoid, killer: Player?, weapon: string)
	print(`[Combat] {victim.Parent} killed by {if killer then killer.Name else "world"} ({weapon})`)
end)
