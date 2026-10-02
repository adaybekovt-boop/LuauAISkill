--!strict
local Parser = {}
export type Command = { verb: string, targetId: number? }
function Parser.parse(text: string): Command?
	if #text > 80 then return nil end
	if string.match(text, "^/respawn%s*$") then return { verb = "respawn" } end
	local idText = string.match(text, "^/kick%s+(%d+)%s*$")
	local id = if idText then tonumber(idText) else nil
	if id and id > 0 and id <= 9007199254740991 and id % 1 == 0 then
		return { verb = "kick", targetId = id }
	end
	return nil
end
function Parser.allowed(caller: number, owner: number, admins: { [number]: boolean }): boolean
	return caller == owner and owner > 0 or admins[caller] == true
end
return Parser
