# Recipe: round manager (Waiting → Intermission → InRound → Results)

## When NOT to use
Do not use in-memory round state as durable tournament or purchase state.

Evidence: state machine CLI-EXECUTED (`examples/tests/rounds.spec.luau`) · server/HUD TYPECHECKED · **not run in
Studio**. Side: server loop + client HUD. Chapter: [architecture](../../handbook/roblox/21-architecture.md),
[cross-server](../../handbook/roblox/07-cross-server.md) (for multi-server games see [matchmaking](matchmaking-queue.md)).

## Architecture
```text
RoundState (pure): step(facts) → phase change | nil
RoundServer: every 0.25 s gather facts (players, alive participants) → step → on change:
   InRound: clone a random map from ServerStorage.Maps, spawn participants at SpawnLocations / "RoundSpawn" parts,
            watch Humanoid.Died
   Results: rewards (winner = last alive, or none on timeout)
   Intermission/Waiting after a round: destroy map, LoadCharacterAsync everyone back to the lobby
   publish: ReplicatedStorage.Round attributes Phase, EndsAt (SERVER TIME), Winner
RoundClient: countdown = EndsAt − Workspace:GetServerTimeNow(), refreshed locally 5×/s
```
Why:
- **Pure state machine** → the tricky transitions (people leaving mid-countdown, everyone dying, timer vs last
  standing) are unit-tested without Studio.
- **Replicate the deadline, not the countdown**: one attribute change per phase instead of one per second per
  client; clients stay in sync via `GetServerTimeNow` (os.clock values are per-machine and must be converted).
- **One loop** owns round flow; gameplay systems react to `Phase` instead of running their own timers.

## Code
<!-- code: examples/rounds/ReplicatedStorage/Rounds/RoundState.luau -->
```luau
-- file: examples/rounds/ReplicatedStorage/Rounds/RoundState.luau
--!strict
-- Pure round state machine (no Roblox APIs; CLI-tested in examples/tests/rounds.spec.luau).
--   Waiting (not enough players) → Intermission (countdown) → InRound (timer / last one standing) → Results → …
-- The server calls step() a few times per second with facts; it returns the phase change (if any).
-- Status: TYPECHECKED + CLI-EXECUTED.
export type Phase = "Waiting" | "Intermission" | "InRound" | "Results"
export type Config = {
	minPlayers: number,
	intermission: number,
	roundLength: number,
	results: number,
	endWhenAliveAtMost: number, -- 1 = last one standing; 0 = only the timer ends the round
}
export type Round = { phase: Phase, endsAt: number, config: Config, winner: string? }
export type Facts = { now: number, players: number, alive: number, lastAlive: string? }

local RoundState = {}

function RoundState.new(config: Config, now: number): Round
	return { phase = "Waiting", endsAt = now, config = config, winner = nil }
end

local function go(r: Round, phase: Phase, now: number, duration: number): Phase
	r.phase = phase
	r.endsAt = now + duration
	return phase
end

-- Returns the new phase when it changed, otherwise nil.
function RoundState.step(r: Round, f: Facts): Phase?
	local c = r.config
	if r.phase == "Waiting" then
		if f.players >= c.minPlayers then
			return go(r, "Intermission", f.now, c.intermission)
		end
	elseif r.phase == "Intermission" then
		if f.players < c.minPlayers then
			return go(r, "Waiting", f.now, 0) -- someone left during the countdown
		elseif f.now >= r.endsAt then
			r.winner = nil
			return go(r, "InRound", f.now, c.roundLength)
		end
	elseif r.phase == "InRound" then
		local lastStanding = c.endWhenAliveAtMost > 0 and f.alive <= c.endWhenAliveAtMost
		if lastStanding or f.now >= r.endsAt then
			r.winner = if lastStanding and f.alive == 1 then f.lastAlive else nil
			return go(r, "Results", f.now, c.results)
		end
	elseif r.phase == "Results" then
		if f.now >= r.endsAt then
			return if f.players >= c.minPlayers then go(r, "Intermission", f.now, c.intermission)
				else go(r, "Waiting", f.now, 0)
		end
	end
	return nil
end

return table.freeze(RoundState)
```
<!-- /code -->

<!-- code: examples/rounds/ServerScriptService/RoundServer.server.luau -->
```luau
-- file: examples/rounds/ServerScriptService/RoundServer.server.luau
--!strict
-- Round loop: drives RoundState from server facts, loads/unloads the map, spawns participants, tracks who is alive.
-- Replication: two attributes on ReplicatedStorage.Round — Phase and EndsAt (server time). Clients compute the
-- countdown locally, so nothing is sent every second.
-- Map contract: ServerStorage.Maps.<Name> (Model) containing SpawnLocations or parts tagged "RoundSpawn".
-- Status: TYPECHECKED (state machine CLI-EXECUTED). Not run in Studio.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local RoundState = require(ReplicatedStorage.Rounds.RoundState)

local CONFIG: RoundState.Config = {
	minPlayers = 2,
	intermission = 15,
	roundLength = 180,
	results = 8,
	endWhenAliveAtMost = 1,
}

local info = Instance.new("Folder")
info.Name = "Round"
info.Parent = ReplicatedStorage

local round = RoundState.new(CONFIG, os.clock())
local participants: { [Player]: boolean } = {} -- true = alive in this round
local currentMap: Model? = nil
local random = Random.new()

local function publish()
	info:SetAttribute("Phase", round.phase)
	-- os.clock() is local to this server; convert to shared server time for clients.
	info:SetAttribute("EndsAt", Workspace:GetServerTimeNow() + (round.endsAt - os.clock()))
	info:SetAttribute("Winner", round.winner)
end

local function loadMap(): Model?
	local maps = ServerStorage:FindFirstChild("Maps")
	local list = if maps then maps:GetChildren() else {}
	if #list == 0 then
		warn("[Round] no maps in ServerStorage.Maps")
		return nil
	end
	local template = list[random:NextInteger(1, #list)]
	if not template:IsA("Model") then
		return nil
	end
	local map = template:Clone() :: Model
	map.Name = "CurrentMap"
	map.Parent = Workspace
	return map
end

local function spawnPoints(map: Model): { BasePart }
	local points: { BasePart } = {}
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") and (d:IsA("SpawnLocation") or CollectionService:HasTag(d, "RoundSpawn")) then
			table.insert(points, d)
		end
	end
	return points
end

local function startRound()
	currentMap = loadMap()
	local points = if currentMap then spawnPoints(currentMap) else {}
	table.clear(participants)
	for i, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if character and humanoid and humanoid.Health > 0 and #points > 0 then
			participants[player] = true
			local spawnPart = points[(i - 1) % #points + 1]
			character:PivotTo(spawnPart.CFrame * CFrame.new(0, 4, 0))
			humanoid.Died:Once(function()
				if participants[player] then
					participants[player] = false
				end
			end)
		end
	end
end

local function endRound()
	table.clear(participants)
	if currentMap then
		currentMap:Destroy() -- big hierarchies: consider chunked destruction to avoid a replication spike
		currentMap = nil
	end
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			player:LoadCharacterAsync() -- back to the lobby spawn
		end)
	end
end

Players.PlayerRemoving:Connect(function(player: Player)
	participants[player] = nil
end)

publish()
while true do
	task.wait(0.25)
	local alive, lastAlive = 0, nil
	for player, isAlive in participants do
		if isAlive then
			alive += 1
			lastAlive = player.Name
		end
	end
	local changed = RoundState.step(round, {
		now = os.clock(),
		players = #Players:GetPlayers(),
		alive = alive,
		lastAlive = lastAlive,
	})
	if changed == "InRound" then
		startRound()
	elseif changed == "Results" then
		-- rewards go here (round.winner is a name; look up the Player if still present)
	elseif changed == "Intermission" or changed == "Waiting" then
		if currentMap then
			endRound()
		end
	end
	if changed then
		publish()
	end
end
```
<!-- /code -->

<!-- code: examples/rounds/StarterPlayer/StarterPlayerScripts/RoundClient.client.luau -->
```luau
-- file: examples/rounds/StarterPlayer/StarterPlayerScripts/RoundClient.client.luau
--!strict
-- Round HUD: reads Phase/EndsAt attributes and counts down locally (no per-second network traffic).
-- Status: TYPECHECKED. Not run in Studio.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local info = ReplicatedStorage:WaitForChild("Round", 30)
assert(info, "ReplicatedStorage.Round missing (is RoundServer running?)")

local gui = Instance.new("ScreenGui")
gui.Name = "RoundHud"
gui.ResetOnSpawn = false
local label = Instance.new("TextLabel")
label.AnchorPoint = Vector2.new(0.5, 0)
label.Position = UDim2.fromScale(0.5, 0.02)
label.Size = UDim2.fromScale(0.3, 0.05)
label.BackgroundTransparency = 1
label.TextScaled = true
label.TextColor3 = Color3.fromRGB(240, 240, 240)
label.TextStrokeTransparency = 0.5
label.Parent = gui
gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")

local TEXT = { Waiting = "Waiting for players", Intermission = "Next round in", InRound = "Time left", Results = "Round over" }

while true do
	local phase = info:GetAttribute("Phase")
	local endsAt = info:GetAttribute("EndsAt")
	local left = if type(endsAt) == "number" then math.max(0, math.ceil(endsAt - Workspace:GetServerTimeNow())) else 0
	local title = if type(phase) == "string" then TEXT[phase] or phase else ""
	if phase == "Results" then
		local winner = info:GetAttribute("Winner")
		label.Text = if type(winner) == "string" then `{winner} wins!` else title
	elseif phase == "Waiting" then
		label.Text = title
	else
		label.Text = `{title} {left // 60}:{string.format("%02d", left % 60)}`
	end
	task.wait(0.2)
end
```
<!-- /code -->

## How to test
- CLI: `luau examples/tests/rounds.spec.luau` (full cycle, timeout, leaving during intermission, everyone dies).
- Studio → Server & Clients with 2–3 players: countdown identical on all clients; map appears at round start,
  disappears after results; dead players stay dead until the round ends (`Players.CharacterAutoLoads` behaviour
  depends on your settings — for spectating set it false and respawn manually).
- 1 player leaves mid-intermission → back to "Waiting for players".
- Late joiner during a round: not a participant; sees the HUD; spawns in the lobby.

## Variations
- Teams/objectives: extend `Facts` (e.g. `teamAlive = {Red = 2, Blue = 0}`) and the end condition — keep it pure.
- Voting for maps: an extra `Voting` phase; clients send one vote (rate-limited, validated against the map list).
- Match servers from [matchmaking](matchmaking-queue.md): set `minPlayers` to the roster size and add a timeout
  that starts anyway.
- Large maps: cloning/destroying huge models spikes replication; stream them in chunks or keep maps in Workspace
  and toggle participation areas instead.

Sources: cd:reference/engine/classes/Workspace, cd:reference/engine/classes/Players, cd:scripting/attributes,
cd:reference/engine/classes/SpawnLocation, cd:performance-optimization/improve.
