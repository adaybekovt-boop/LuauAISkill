--!strict
-- Damage: the single server entry point for hurting anything. Handles alive/team/invulnerability checks,
-- ForceField (via Humanoid:TakeDamage), kill credit and a `killed` signal for rewards/kill feed.
-- Status: TYPECHECKED. Not run in Studio.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Lib.Signal)

export type Source = { attacker: Player?, weapon: string, headshot: boolean? }

local CREDIT_WINDOW = 10 -- seconds: a fall/reset shortly after being hit still credits the attacker
local FRIENDLY_FIRE = false

local Damage = {}
-- killed(victimHumanoid, killer: Player?, weapon)
Damage.killed = Signal.new() :: Signal.Signal<Humanoid, Player?, string>
-- damaged(victimHumanoid, amount, source) — for hit markers/indicators (server → client notification is up to you)
Damage.damaged = Signal.new() :: Signal.Signal<Humanoid, number, Source>

type Record = { attacker: Player?, weapon: string, time: number, diedConn: RBXScriptConnection }
local lastHit: { [Humanoid]: Record } = {}

local function sameTeam(a: Player, b: Player): boolean
	return not a.Neutral and not b.Neutral and a.Team == b.Team -- Neutral players have no team
end

local function track(humanoid: Humanoid, source: Source)
	local record = lastHit[humanoid]
	if record then
		record.attacker, record.weapon, record.time = source.attacker, source.weapon, os.clock()
		return
	end
	local conn: RBXScriptConnection
	conn = humanoid.Died:Connect(function()
		conn:Disconnect()
		local r = lastHit[humanoid]
		lastHit[humanoid] = nil
		local credited = r and os.clock() - r.time <= CREDIT_WINDOW
		Damage.killed:fire(humanoid, if credited and r then r.attacker else nil, if r then r.weapon else "Unknown")
	end)
	lastHit[humanoid] = { attacker = source.attacker, weapon = source.weapon, time = os.clock(), diedConn = conn }
	humanoid.Destroying:Once(function()
		local r = lastHit[humanoid]
		if r then
			r.diedConn:Disconnect()
			lastHit[humanoid] = nil
		end
	end)
end

-- Returns true if damage was applied. `amount` is computed by the SERVER (weapon config), never by a client.
function Damage.apply(target: Humanoid, amount: number, source: Source): boolean
	if amount ~= amount or amount <= 0 or target.Health <= 0 then
		return false
	end
	local model = target.Parent
	if not model or not model:IsA("Model") then
		return false
	end
	local victimPlayer = Players:GetPlayerFromCharacter(model)
	local attacker = source.attacker
	if attacker and victimPlayer then
		if attacker == victimPlayer then
			return false
		end
		if not FRIENDLY_FIRE and sameTeam(attacker, victimPlayer) then
			return false
		end
	end
	local invulnerableUntil = model:GetAttribute("InvulnerableUntil")
	if type(invulnerableUntil) == "number" and os.clock() < invulnerableUntil then
		return false -- i-frames (dodge, spawn protection) set by server code only
	end
	amount = math.floor(amount + 0.5) -- round once, here
	track(target, source)
	target:TakeDamage(amount) -- respects ForceField; set Health directly for custom rules
	Damage.damaged:fire(target, amount, source)
	return true
end

return Damage
