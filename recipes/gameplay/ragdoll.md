# Recipe: ragdoll (death and knock-down, R15/R6, reversible)

## When NOT to use
Do not apply this rig-specific setup to arbitrary custom rigs without adapting constraints and cleanup.

Evidence: TYPECHECKED · **not run in Studio** (ragdoll feel and stability must be tuned in Studio).
Side: server builds constraints; the owning client switches its Humanoid state. Part of `examples/combat`.
Chapter: [combat → ragdoll](../../handbook/roblox/15-combat.md#ragdoll-on-death-or-knock-down).

## Architecture
```text
CharacterAdded (server): Humanoid.BreakJointsOnDeath = false
Died (server): Ragdoll.enable(character)
    for each Motor6D: Attachment at C0 on Part0, Attachment at C1 on Part1 → BallSocketConstraint (limits)
                      + NoCollisionConstraint(Part0, Part1) → Motor6D.Enabled = false → limbs CanCollide
    root CanCollide = false
Knock-down (alive): Ragdoll.knockDown(character, seconds) → same + RagdollState remote → owner client
    Humanoid:ChangeState(Physics) … later GettingUp; server re-enables Motor6Ds and removes constraints
NPCs (server-owned): the server changes the Humanoid state itself
```
Why:
- **Disable, don't destroy, Motor6Ds** → the same character can get back up (knock-down) and animations resume.
- **Attachments at C0/C1** keep each limb exactly where the joint was → no snapping on activation.
- **Only the network owner can change a player's Humanoid state**; server-side `ChangeState` on a player's
  character is ignored/overridden by the owner. Hence the remote.
- **NoCollisionConstraints** between jointed limbs prevent jitter explosions.

## Code
<!-- code: examples/combat/ServerScriptService/Combat/Ragdoll.luau -->
```luau
-- file: examples/combat/ServerScriptService/Combat/Ragdoll.luau
--!strict
-- Ragdoll: replace Motor6Ds with BallSocketConstraints (reversible). Works for R15 and R6.
-- Death ragdoll: server-only (dead Humanoids don't fight physics). Knock-down of a LIVING player: the owning
-- client must also put its Humanoid into the Physics state (RagdollClient.client.luau) — the server can't,
-- because player characters are simulated by their owner.
-- Status: TYPECHECKED. Not run in Studio.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ragdoll = {}

local stateRemote: RemoteEvent? = nil
local function remote(): RemoteEvent
	if stateRemote then
		return stateRemote
	end
	local r = Instance.new("RemoteEvent")
	r.Name = "RagdollState"
	r.Parent = ReplicatedStorage
	stateRemote = r
	return r
end

-- Call once when the character spawns (server): keep joints on death so we can ragdoll instead of falling apart.
function Ragdoll.prepare(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.BreakJointsOnDeath = false
	end
	remote() -- make sure the remote exists before clients look for it
end

function Ragdoll.enable(character: Model)
	if character:GetAttribute("Ragdolled") == true then
		return
	end
	character:SetAttribute("Ragdolled", true)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- Docs: with RequiresNeck the character dies if the Neck Motor6D is "removed or disconnected even
		-- momentarily". Whether Enabled=false counts isn't documented, so turn it off for alive knock-downs.
		humanoid.RequiresNeck = false
	end
	for _, motor in character:GetDescendants() do
		if not motor:IsA("Motor6D") or not motor.Part0 or not motor.Part1 then
			continue
		end
		local part0, part1 = motor.Part0 :: BasePart, motor.Part1 :: BasePart
		local a0 = Instance.new("Attachment")
		a0.Name = "RagdollA0"
		a0.CFrame = motor.C0
		a0.Parent = part0
		local a1 = Instance.new("Attachment")
		a1.Name = "RagdollA1"
		a1.CFrame = motor.C1
		a1.Parent = part1
		local socket = Instance.new("BallSocketConstraint")
		socket.Name = "RagdollSocket"
		socket.Attachment0 = a0
		socket.Attachment1 = a1
		socket.LimitsEnabled = true
		socket.UpperAngle = if part1.Name:find("Head") then 30 else 60
		socket.TwistLimitsEnabled = true
		socket.TwistLowerAngle = -45
		socket.TwistUpperAngle = 45
		socket.Parent = part0
		local noCollide = Instance.new("NoCollisionConstraint") -- adjacent limbs would jitter against each other
		noCollide.Name = "RagdollNoCollide"
		noCollide.Part0 = part0
		noCollide.Part1 = part1
		noCollide.Parent = part0
		motor.Enabled = false
		if part1.Name ~= "HumanoidRootPart" then
			part1.CanCollide = true
		end
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.CanCollide = false -- the invisible root box would prop the body up
	end
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		remote():FireClient(player, true)
	elseif humanoid and humanoid.Health > 0 then
		humanoid:ChangeState(Enum.HumanoidStateType.Physics) -- server-owned NPC
	end
end

function Ragdoll.disable(character: Model)
	if character:GetAttribute("Ragdolled") ~= true then
		return
	end
	character:SetAttribute("Ragdolled", nil)
	for _, d in character:GetDescendants() do
		if d:IsA("Motor6D") then
			d.Enabled = true
		elseif d.Name:sub(1, 7) == "Ragdoll" and (d:IsA("Constraint") or d:IsA("Attachment")
			or d:IsA("NoCollisionConstraint")) then
			d:Destroy()
		end
	end
	local player = Players:GetPlayerFromCharacter(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.RequiresNeck = true
	end
	if player then
		remote():FireClient(player, false)
	elseif humanoid and humanoid.Health > 0 then
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
	-- Limb CanCollide is managed by the Humanoid again once it leaves the Physics state.
end

-- Temporary knock-down (alive). Returns immediately.
function Ragdoll.knockDown(character: Model, seconds: number)
	Ragdoll.enable(character)
	task.delay(seconds, function()
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if character.Parent and humanoid and humanoid.Health > 0 then
			Ragdoll.disable(character)
		end
	end)
end

return Ragdoll
```
<!-- /code -->

<!-- code: examples/combat/StarterPlayer/StarterPlayerScripts/RagdollClient.client.luau -->
```luau
-- file: examples/combat/StarterPlayer/StarterPlayerScripts/RagdollClient.client.luau
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
```
<!-- /code -->

## Tuning (in Studio)
| Symptom | Fix |
|---|---|
| Body explodes/jitters | missing NoCollisionConstraints; limbs overlapping at spawn; reduce `UpperAngle` |
| Neck bends unnaturally | head `UpperAngle` 20–30°, twist ±30° |
| Body slides like ice | increase limb `CustomPhysicalProperties` friction |
| Ragdoll floats/stands | root still colliding (set `CanCollide=false`), or Humanoid not in `Physics` (owner side) |
| Dead character disappears too soon | `Players.RespawnTime`; or clone the ragdoll into a corpse model before respawn |

## How to test
- Die from damage: body collapses on all clients, no parts fall apart, no errors.
- `Ragdoll.knockDown(character, 2)` from the server command bar (Server & Clients): collapses, gets up after 2 s,
  animations resume, can walk.
- NPC (server-owned rig with Humanoid): knock-down works without any client.
- R6 and R15 rigs.

## Pitfalls
- `Humanoid.RequiresNeck` (default true): per the docs the character dies if the Neck Motor6D is "removed or
  disconnected even momentarily". Whether `Enabled = false` counts is not documented, so the code turns
  `RequiresNeck` off while ragdolled and back on when standing up. Verify in Studio with a knock-down.
- Layered clothing/accessories are welded to limbs and follow automatically; don't ragdoll accessories.
- Ragdolls are physics-heavy: many simultaneous corpses → remove after a few seconds on low-end devices.

Sources: cd:physics/constraints/ball-socket, cd:physics/constraints/no-collision, cd:reference/engine/classes/Humanoid,
cd:reference/engine/classes/Motor6D, cd:physics/network-ownership, cd:characters/index.
