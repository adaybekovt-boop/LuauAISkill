--!strict
-- Owner-side half of the ragdoll: the local player's character is simulated by this client, so only this client
-- can put its Humanoid into the Physics state (and back). The server builds/removes the constraints.
-- Status: TYPECHECKED. Not run in Studio.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer :: Player
local stateRemote = ReplicatedStorage:WaitForChild("RagdollState", 30)
assert(stateRemote and stateRemote:IsA("RemoteEvent"), "RagdollState remote missing")

stateRemote.OnClientEvent:Connect(function(on: boolean)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return -- dead Humanoids don't fight physics; nothing to do
	end
	if on then
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	else
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end)
