--!strict
-- Opt-in Studio-only fixture: no production DataStores, purchases or third-party assets.
local RunService = game:GetService("RunService")
local StudioTestService = game:GetService("StudioTestService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Protocol = require(ReplicatedStorage.Regression.Protocol)
if not RunService:IsStudio() then return end
local ok, args = pcall(function() return StudioTestService:GetTestArgs() end)
if not ok or type(args) ~= "table" or args.suite ~= "recipe-regression-v1" then return end
local rows: { Protocol.Receipt } = {}
local connections: { RBXScriptConnection } = {}
local remote = Instance.new("RemoteEvent")
remote.Name = "RegressionPeer"; remote.Parent = ReplicatedStorage
local fixture = Instance.new("Folder")
fixture.Name = "RegressionState"; fixture:SetAttribute("Revision", 0); fixture.Parent = ReplicatedStorage
local acknowledgments: { [number]: string } = {}
local ready: { [number]: boolean } = {}
local left: { [number]: boolean } = {}
local phase = "boot"
local revision = 0
local function check(name: string, condition: boolean, detail: string)
	table.insert(rows, { name = name, ok = condition, detail = detail })
end
local function waitFor(label: string, predicate: () -> boolean): boolean
	local deadline = os.clock() + 15
	while not predicate() and os.clock() < deadline do task.wait(0.05) end
	local success = predicate(); check(label, success, if success then "condition observed" else "15-second timeout")
	return success
end
table.insert(connections, remote.OnServerEvent:Connect(function(player: Player, verb: any, value: any)
	if verb == "ready" then ready[player.UserId] = true
	elseif verb == "ack" and value == phase then acknowledgments[player.UserId] = value
	elseif verb == "forge" then
		-- Deliberately ignored. Fixture state has one server writer, irrespective of client payload.
	end
end))
table.insert(connections, Players.PlayerRemoving:Connect(function(player) left[player.UserId] = true end))
local function ids(players: { Player }): { number }
	local result: { number } = {}
	for _, player in players do table.insert(result, player.UserId) end
	return result
end
local function stage(name: string, peers: { Player })
	phase = name; acknowledgments = {}; revision += 1
	fixture:SetAttribute("Revision", revision)
	for _, player in peers do remote:FireClient(player, "observe", name, revision) end
	waitFor("all peers observed " .. name, function()
		return Protocol.complete(ids(peers), acknowledgments, name)
	end)
end
local function scenario()
	local function initialReady(): boolean
		local list = Players:GetPlayers()
		return #list == 2 and ready[list[1].UserId] == true and ready[list[2].UserId] == true
	end
	local initiallyReady = waitFor("two initial clients ready", initialReady)
	if not initiallyReady then return end
	local initial = Players:GetPlayers()
	table.sort(initial, function(a: Player, b: Player) return a.UserId < b.UserId end)
	stage("initial-replication", initial)
	local oldCharacter = initial[1].Character
	initial[1]:LoadCharacterAsync()
	waitFor("respawn replaced character", function()
		return initial[1].Character ~= nil and initial[1].Character ~= oldCharacter
	end)
	stage("after-respawn", initial)
	StudioTestService:AddPlayers(1)
	local function allReady(): boolean
		local list = Players:GetPlayers()
		if #list ~= 3 then return false end
		for _, player in list do if not ready[player.UserId] then return false end end
		return true
	end
	local lateReady = waitFor("late join ready", allReady)
	if not lateReady then return end
	stage("late-join-replication", Players:GetPlayers())
	local expected = fixture:GetAttribute("Revision")
	phase = "reject-forgery"; acknowledgments = {}
	for _, player in initial do remote:FireClient(player, "forge", phase, revision) end
	waitFor("forgery attempted by both clients", function()
		return Protocol.complete(ids(initial), acknowledgments, phase)
	end)
	check("client payload did not change server state", fixture:GetAttribute("Revision") == expected,
		"server revision remains authoritative")
	remote:FireClient(initial[2], "leave", "disconnect", 0)
	waitFor("selected client disconnected", function() return left[initial[2].UserId] == true end)
	stage("survivor-replication", Players:GetPlayers())
end
local complete = false
local function finish()
	if complete then return end
	complete = true
	for _, connection in connections do connection:Disconnect() end
	remote:Destroy(); fixture:Destroy()
	local result = Protocol.result(rows)
	print("REGRESSION_RESULT " .. HttpService:JSONEncode(result))
	StudioTestService:EndTest(result)
end
task.delay(120, function()
	if not complete then check("suite deadline", false, "120-second watchdog"); finish() end
end)
local failure: string? = nil
local success = xpcall(scenario, function(err: any) failure = debug.traceback(tostring(err)) end)
if not success then check("unexpected server error", false, failure or "unknown error") end
finish()
