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
