--!strict
local function handle(_player: Player, payload: any)
	local damage = payload.damage :: number
	print(damage + 1)
end
return handle
