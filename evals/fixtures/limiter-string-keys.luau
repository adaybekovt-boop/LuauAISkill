-- BAD: intentionally broken eval fixture (do not copy). A rate limiter that makes the server run out of memory.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local action = ReplicatedStorage:WaitForChild("Action")
local lastCall = {}

action.OnServerEvent:Connect(function(player, actionName, ...)
	local key = player.UserId .. ":" .. actionName
	if lastCall[key] and os.clock() - lastCall[key] < 0.2 then
		return
	end
	lastCall[key] = os.clock()
	-- dispatch by name
	local handler = _G.Handlers[actionName]
	handler(player, ...)
end)
