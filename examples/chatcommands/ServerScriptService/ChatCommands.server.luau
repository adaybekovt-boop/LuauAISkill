--!strict
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Parser = require(script.Parent.Commands.Parser)
local TokenBucket = require(ReplicatedStorage.Lib.TokenBucket)
-- Set real moderator UserIds here. Empty = experience owner only for user-owned experiences.
local ADMINS: { [number]: boolean } = {}
local owner = if game.CreatorType == Enum.CreatorType.User then game.CreatorId else 0
local limiter = TokenBucket.new({ command = { capacity = 2, rate = 0.2 } }) :: TokenBucket.Limiter<Player>
local busy: { [Player]: boolean } = {}
local commands: { TextChatCommand } = {}
local connections: { RBXScriptConnection } = {}
local function authorized(player: Player): boolean
	return Parser.allowed(player.UserId, owner, ADMINS)
end
local function execute(source: TextSource, text: string)
	local caller = Players:GetPlayerByUserId(source.UserId)
	if not caller then return end
	if not limiter:allow(caller, "command", os.clock()) or busy[caller] then return end
	local command = Parser.parse(text)
	if not command then return end
	if command.verb == "respawn" then
		-- Self-service only. Add your round/combat eligibility rule before enabling in a real game.
		if caller:GetAttribute("AllowRespawnCommand") ~= true then return end
		busy[caller] = true
		local ok = pcall(function() caller:LoadCharacterAsync() end)
		busy[caller] = nil
		if not ok then warn("[Commands] Respawn failed for user", caller.UserId) end
	elseif authorized(caller) and command.targetId then
		local target = Players:GetPlayerByUserId(command.targetId)
		if target and target ~= caller and not authorized(target) then
			target:Kick("Removed by a moderator") -- static text only; input is UNFILTERED
		end
	end
end
for _, alias in { "/respawn", "/kick" } do
	local command = Instance.new("TextChatCommand")
	command.Name = "Secure" .. string.sub(alias, 2)
	command.PrimaryAlias = alias
	command.Parent = TextChatService
	table.insert(commands, command)
	table.insert(connections, command.Triggered:Connect(execute))
end
table.insert(connections, Players.PlayerRemoving:Connect(function(player)
	limiter:forget(player); busy[player] = nil
end))
script.Destroying:Connect(function()
	for _, c in connections do c:Disconnect() end
	for _, command in commands do command:Destroy() end
	for _, player in Players:GetPlayers() do limiter:forget(player) end
end)
