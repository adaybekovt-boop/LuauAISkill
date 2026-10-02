--!strict
-- Bounded coordination for an isolated test place. NOT RUN in Roblox.
-- Client results are smoke observations, never production authorization/security decisions.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type Assertion = { id: string, status: string, detail: string }
export type Context = {
	assertions: { Assertion },
	players: { Player },
	check: (string, boolean, string?) -> (),
	waitFor: (string, () -> boolean, number?) -> (),
	client: (Player, string, any?) -> any,
	close: () -> (),
}

local Context = {}

function Context.child(parent: Instance, name: string): Instance
	local instance = parent:WaitForChild(name, 15)
	assert(instance, `missing {parent:GetFullName()}.{name}`)
	return instance
end

function Context.module(parent: Instance, name: string): any
	local instance = Context.child(parent, name)
	assert(instance:IsA("ModuleScript"), "expected ModuleScript: " .. name)
	-- Fixture modules differ per isolated project; their sources are typechecked in their original example.
	local loadModule: (ModuleScript) -> any = require :: any
	return loadModule(instance)
end

function Context.new(clientCount: number): Context
	local assertions: { Assertion } = {}
	local remote = Instance.new("RemoteEvent")
	remote.Name = "ReleaseSmokeControl"
	remote.Parent = ReplicatedStorage
	local ready: { [Player]: boolean } = {}
	local responses: { [string]: any } = {}
	local expected: { [string]: Player } = {}
	local seq = 0
	local connection = remote.OnServerEvent:Connect(function(player: Player, id: unknown, response: unknown)
		if id == "ready" then
			ready[player] = true
		elseif type(id) == "string" and expected[id] == player and type(response) == "table" then
			responses[id] = response
		end
	end)
	local function waitFor(label: string, predicate: () -> boolean, timeout: number?)
		local deadline = os.clock() + (timeout or 15)
		repeat
			if predicate() then
				return
			end
			task.wait(0.05)
		until os.clock() >= deadline
		error("timeout: " .. label)
	end
	local peers: { Player } = {}
	local ok, err = pcall(function()
		if clientCount > 0 then
			waitFor("client ready handshakes", function()
				table.clear(peers)
				for _, player in Players:GetPlayers() do
					if ready[player] then
						table.insert(peers, player)
					end
				end
				return #peers >= clientCount
			end, 45)
		end
	end)
	if not ok then
		connection:Disconnect()
		remote:Destroy()
		error(err)
	end
	table.sort(peers, function(a: Player, b: Player): boolean return a.UserId < b.UserId end)
	return {
		assertions = assertions,
		players = peers,
		check = function(id: string, passed: boolean, detail: string?)
			table.insert(assertions, { id = id, status = if passed then "PASS" else "FAIL", detail = detail or "" })
			assert(passed, id .. ": " .. (detail or "assertion failed"))
		end,
		waitFor = waitFor,
		client = function(player: Player, action: string, data: any?): any
			seq += 1
			local id = tostring(seq)
			expected[id] = player
			remote:FireClient(player, id, action, data)
			waitFor("client " .. action, function() return responses[id] ~= nil end, 35)
			local response = responses[id]
			responses[id], expected[id] = nil, nil
			assert(response.ok == true, tostring(response.error))
			return response.value
		end,
		close = function()
			connection:Disconnect()
			remote:Destroy()
		end,
	}
end

return Context
