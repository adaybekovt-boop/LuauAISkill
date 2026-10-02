# Authorized TextChatService commands

Server-owned `/kick <UserId>` and explicitly enabled self `/respawn` commands with exact parsing,
per-player limits, no display-name matching, and no rebroadcast of unfiltered command text.

Evidence: **TYPECHECKED** (strict, old + new solver, pinned Roblox definitions); pure logic **CLI-EXECUTED**.
**Studio / live: NOT RUN.**

## Architecture
- `TextChatCommand.Triggered` supplies a TextSource identity and unfiltered text. Identity resolves back to the
  currently connected Player on the server; matching the alias alone grants no authority.
- Only the user-owned experience's creator or explicit server-side UserId allowlist can kick. Group experiences
  require configured moderators; no unverified group rank assumptions or client attributes confer permission.
- Parser accepts only a bounded exact grammar. `/kick` uses a numeric UserId, rejects extra arguments and protects
  self / other authorized moderators. Kick reason is constant, not interpolated user input.
- Self-respawn also requires server-owned `AllowRespawnCommand == true`; a per-player busy flag prevents overlapping
  yielding respawns. All expensive work is behind the shared token bucket.
- Destroying the owner script disconnects handlers and destroys its commands. Player removal clears limiter state.

## When NOT to use

not a permission framework, ban database, audited moderator dashboard, or free-form chat
replacement. If your project already has role authorization, route these handlers through it rather than inventing
another administrator list. Do not enable self-respawn during competitive rounds without an eligibility rule.

## Setup and integration
Copy `examples/chatcommands/ServerScriptService` and shared `examples/lib/ReplicatedStorage/Lib`.
Set actual moderator UserIds in the private `ADMINS` table; names and client-supplied permission claims are invalid.
Have your server round/spawn logic set `AllowRespawnCommand` on players who may use it. Use unique aliases if your
experience already owns `/kick` or `/respawn`. No client chat remote or LocalScript is needed.

## Implementation

### `examples/chatcommands/ServerScriptService/ChatCommands.server.luau`

<!-- code: examples/chatcommands/ServerScriptService/ChatCommands.server.luau -->
```luau
-- file: examples/chatcommands/ServerScriptService/ChatCommands.server.luau
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
```
<!-- /code -->

### `examples/chatcommands/ServerScriptService/Commands/Parser.luau`

<!-- code: examples/chatcommands/ServerScriptService/Commands/Parser.luau -->
```luau
-- file: examples/chatcommands/ServerScriptService/Commands/Parser.luau
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
```
<!-- /code -->

## How to test

| Scenario | Required observation |
|---|---|
| CLI malformed grammar | Names, fractional/negative IDs, extra text, and long payloads rejected |
| Server & Clients, unauthorized caller | `/kick` has no effect and exposes no unfiltered text |
| Authorized moderator, ordinary target | Exact UserId target is removed with the static reason |
| Spoofed display name / protected target | No name-based escalation; self/moderator target is protected |
| Respawn disabled / busy / flooded | No respawn; repeated requests remain bounded |
| Destroy/reinstall script | No duplicate commands or surviving connections |

Temporarily configure test moderator UserIds in a private test place; do not weaken production authorization for testing.

## Failure paths and limits
Unfiltered text must never enter logs shown to users, system messages, kick reasons, or other remotes. If future
commands display user-provided names/text, add the documented TextService filtering path and fail closed on errors.
Role/group lookups can yield: cache a verified server authorization result with explicit expiry and revocation
semantics, and re-check connected identity after a yield. This sample deliberately avoids that extra trust boundary.

## Verification
From the skill directory, run `python tools/check_all.py`. Pure tests for this recipe:
`luau examples/tests/chatcommands.spec.luau`. The checker runs both Luau solvers. Engine coverage remains NOT RUN until you retain
assertion output from the specified Studio scenario with Studio build, place revision, peers, and device.

Sources: cd:chat/in-experience-text-chat, cd:chat/examples/custom-text-chat-commands, cd:reference/engine/classes/TextChatCommand, api:TextChatCommand.Triggered, api:Player.LoadCharacterAsync.
