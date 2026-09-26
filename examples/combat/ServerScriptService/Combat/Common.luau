--!strict
-- Shared server helpers for weapons: remotes, equipped-weapon lookup, per-player state, flood guard, shot checks.
-- Status: TYPECHECKED. Not run in Studio.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local TokenBucket = require(ReplicatedStorage.Lib.TokenBucket)
local Validate = require(ReplicatedStorage.Lib.Validate)
local Weapons = require(ReplicatedStorage.Combat.Weapons)

local Common = {}

Common.MAX_ORIGIN_OFFSET = 8 -- studs between a claimed shot origin and the server-side head (latency + muzzle)
Common.FIRE_TOLERANCE = 0.15 -- accept shots up to 15 % faster than rpm (network jitter bunches packets)

export type State = { lastFire: number, busyUntil: number, reloadingUntil: number }
local states: { [Player]: State } = {}
local limiter = TokenBucket.new({ Combat = { capacity = 20, rate = 15 } }) -- coarse flood guard for all weapon remotes

local folder = ReplicatedStorage:FindFirstChild("CombatRemotes")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "CombatRemotes"
	folder.Parent = ReplicatedStorage
end

function Common.remote(name: string, unreliable: boolean?): Instance
	local r = Instance.new(if unreliable then "UnreliableRemoteEvent" else "RemoteEvent")
	r.Name = name
	r.Parent = folder
	return r
end

Common.hitConfirm = Common.remote("HitConfirm") :: RemoteEvent -- server → attacker: (amount, headshot)

function Common.allow(player: Player): boolean
	return limiter:allow(player, "Combat", os.clock())
end

function Common.state(player: Player): State
	local s = states[player]
	if not s then
		s = { lastFire = -math.huge, busyUntil = 0, reloadingUntil = 0 }
		states[player] = s
	end
	return s
end

function Common.forget(player: Player)
	states[player] = nil
	limiter:forget(player)
end

-- The weapon the SERVER sees equipped (Tool parented to the living character) and its config.
function Common.equipped(player: Player): (Model?, Humanoid?, Tool?, Weapons.Weapon?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return nil, nil, nil, nil
	end
	local tool = character:FindFirstChildOfClass("Tool")
	local id = tool and tool:GetAttribute("WeaponId")
	return character, humanoid, tool, if type(id) == "string" then Weapons[id] else nil
end

function Common.humanoidOf(inst: Instance): Humanoid?
	local model = inst:FindFirstAncestorOfClass("Model")
	while model do
		local h = model:FindFirstChildOfClass("Humanoid")
		if h then
			return h
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

function Common.excludeParams(exclude: { Instance }): RaycastParams
	local params = RaycastParams.new()
	params.ExcludeInstances = exclude
	return params
end

-- World geometry between two points? (hits on characters don't count as blocking)
function Common.blocked(from: Vector3, to: Vector3, exclude: { Instance }): boolean
	local hit = Workspace:Raycast(from, to - from, Common.excludeParams(exclude))
	return hit ~= nil and Common.humanoidOf(hit.Instance) == nil
end

-- Validates a client-claimed shot (origin near the head, not through a wall; unit direction). nil = reject.
function Common.shot(character: Model, rawOrigin: unknown, rawDirection: unknown): (Vector3?, Vector3?)
	local origin = Validate.vector3(rawOrigin, 1e6)
	local direction = Validate.unitVector(rawDirection, 0.02)
	local head = character:FindFirstChild("Head")
	if not origin or not direction or not head or not head:IsA("BasePart") then
		return nil, nil
	end
	if (origin - head.Position).Magnitude > Common.MAX_ORIGIN_OFFSET
		or Common.blocked(head.Position, origin, { character }) then
		return nil, nil
	end
	return origin, direction
end

return Common
