--!strict
-- Client weapons: input → local feedback (tracer, sound/anim hooks) → intent to the server. Renders other players'
-- tracers and every projectile from server messages. Never decides hits or damage.
-- Status: TYPECHECKED. Not run in Studio.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Weapons = require(ReplicatedStorage.Combat.Weapons)
local CombatMath = require(ReplicatedStorage.Combat.CombatMath)

local player = Players.LocalPlayer :: Player
local remotes = ReplicatedStorage:WaitForChild("CombatRemotes", 30)
assert(remotes, "CombatRemotes missing (is WeaponServer running?)")
local function get(name: string): any
	return remotes:WaitForChild(name, 30)
end
local meleeSwing: RemoteEvent = get("MeleeSwing")
local hitscanFire: RemoteEvent = get("HitscanFire")
local projectileLaunch: RemoteEvent = get("ProjectileLaunch")
local reload: RemoteEvent = get("Reload")
local shotFx: UnreliableRemoteEvent = get("ShotFx")
local projectileSpawn: RemoteEvent = get("ProjectileSpawn")
local projectileHit: RemoteEvent = get("ProjectileHit")
local hitConfirm: RemoteEvent = get("HitConfirm")

local fxFolder = Instance.new("Folder")
fxFolder.Name = "LocalCombatFx" -- client-only instances, never replicated
fxFolder.Parent = Workspace

local function fxPart(size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false -- our own raycasts must not hit visuals
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = size
	return p
end

local function tracer(from: Vector3, to: Vector3)
	local length = (to - from).Magnitude
	if length < 0.5 then
		return
	end
	local p = fxPart(Vector3.new(0.06, 0.06, length), Color3.fromRGB(255, 225, 160))
	p.CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -length / 2)
	p.Parent = fxFolder
	task.delay(0.05, p.Destroy, p)
end

-- Aim: find what the camera looks at, then fire from the head toward that point (works in 1st and 3rd person).
local function aim(range: number): (Vector3?, Vector3?)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local camera = Workspace.CurrentCamera
	if not character or not head or not head:IsA("BasePart") or not camera then
		return nil, nil
	end
	local params = RaycastParams.new()
	params.ExcludeInstances = { character, fxFolder }
	local ray = camera:ViewportPointToRay(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * range, params)
	local target = if hit then hit.Position else ray.Origin + ray.Direction * range
	local origin = head.Position
	local dir = target - origin
	if dir.Magnitude < 1e-3 then
		return nil, nil
	end
	return origin, dir.Unit
end

local function equippedWeapon(): (Tool?, Weapons.Weapon?)
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	local id = tool and tool:GetAttribute("WeaponId")
	return tool, if type(id) == "string" then Weapons[id] else nil
end

local lastLocalFire = -math.huge
local function onActivated()
	local tool, def = equippedWeapon()
	if not tool or not def then
		return
	end
	local now = os.clock()
	if def.kind == "Hitscan" then
		local gun = def :: Weapons.Hitscan
		local ammo = tool:GetAttribute("Ammo")
		if (type(ammo) == "number" and ammo <= 0) or not CombatMath.canFire(lastLocalFire, now, gun.rpm, 0) then
			return -- client-side gating mirrors the server so honest players never get rejected shots
		end
		local origin, direction = aim(gun.range)
		if origin and direction then
			lastLocalFire = now
			local params = RaycastParams.new()
			params.ExcludeInstances = { player.Character :: Model, fxFolder }
			local predicted = Workspace:Raycast(origin, direction * gun.range, params)
			tracer(origin, if predicted then predicted.Position else origin + direction * gun.range)
			hitscanFire:FireServer(origin, direction)
		end
	elseif def.kind == "Melee" then
		meleeSwing:FireServer() -- play the swing animation here (Animator on the character) for instant feedback
	elseif def.kind == "Projectile" then
		local launcher = def :: Weapons.Projectile
		if not CombatMath.canFire(lastLocalFire, now, launcher.rpm, 0) then
			return
		end
		local origin, direction = aim(500)
		if origin and direction then
			lastLocalFire = now
			projectileLaunch:FireServer(origin, direction)
		end
	end
end

-- Bind Activated for whichever weapon Tool gets equipped.
local toolConn: RBXScriptConnection? = nil
local function watchCharacter(character: Model)
	character.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Tool") and child:GetAttribute("WeaponId") ~= nil then
			if toolConn then
				toolConn:Disconnect()
			end
			toolConn = child.Activated:Connect(onActivated)
		end
	end)
	character.ChildRemoved:Connect(function(child: Instance)
		if child:IsA("Tool") and toolConn then
			toolConn:Disconnect()
			toolConn = nil
		end
	end)
end
player.CharacterAdded:Connect(watchCharacter)
if player.Character then
	watchCharacter(player.Character)
end

ContextActionService:BindAction("Reload", function(_name: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		reload:FireServer()
	end
	return Enum.ContextActionResult.Pass
end, true, Enum.KeyCode.R, Enum.KeyCode.ButtonX)

-- Other players' tracers (own shots were already drawn locally).
shotFx.OnClientEvent:Connect(function(shooterId: number, from: Vector3, to: Vector3)
	if shooterId ~= player.UserId then
		tracer(from, to)
	end
end)

hitConfirm.OnClientEvent:Connect(function(amount: number, headshot: boolean)
	-- Hit marker / sound hook. Server-confirmed, so it never lies about hits.
	print(`hit {math.floor(amount)}{if headshot then " (head)" else ""}`)
end)

-- Projectile visuals: every client simulates the server's curve from the spawn time.
type Visual = { part: Part, origin: Vector3, velocity: Vector3, gravity: Vector3, spawnTime: number }
local visuals: { [number]: Visual } = {}

projectileSpawn.OnClientEvent:Connect(function(id: number, origin: Vector3, velocity: Vector3, gravity: number,
	serverTime: number)
	local part = fxPart(Vector3.new(0.5, 0.5, 0.5), Color3.fromRGB(255, 90, 50))
	part.Shape = Enum.PartType.Ball
	part.Parent = fxFolder
	visuals[id] = {
		part = part,
		origin = origin,
		velocity = velocity,
		gravity = Vector3.new(0, -gravity, 0),
		spawnTime = serverTime,
	}
end)

projectileHit.OnClientEvent:Connect(function(id: number, _at: Vector3)
	local v = visuals[id]
	if v then
		visuals[id] = nil
		v.part:Destroy() -- spawn an explosion effect at `_at` here
	end
end)

RunService.PreRender:Connect(function()
	local now = Workspace:GetServerTimeNow()
	for id, v in visuals do
		local t = now - v.spawnTime
		if t > 10 then -- hit message lost or never sent: don't leak
			visuals[id] = nil
			v.part:Destroy()
			continue
		end
		v.part.Position = CombatMath.ballistic(v.origin, v.velocity, v.gravity, t)
	end
end)
