# Text chat (TextChatService), chat commands, leaderboards

## TL;DR
- Use supported text chat and preserve filtering.
- Authorize chat commands on the server.
- Keep command parsing separate from privileged execution.
- Choose friend, in-server, or global leaderboards deliberately.
- Keep durable scores authoritative and bound leaderboard refresh work.

Read when: chat customization, chat commands (admin, emotes, `/trade`), system messages, private/team channels,
global or friend leaderboards. Related: [security](04-security.md) (admin checks), [data persistence](06-data-persistence.md)
(OrderedDataStore basics, budgets), [UI](18-ui-ux.md).

## TextChatService is the only chat system
Legacy Lua chat (`Chat` service modules, forked ChatScripts) was deprecated; Roblox migrated remaining experiences
automatically in May 2025. Write everything against `TextChatService`; never broadcast player text through your own
RemoteEvents (that skips filtering and violates policy).

| Piece | Where | Use |
|---|---|---|
| `TextChannel` (`RBXGeneral`, `RBXSystem` by default) | server creates/owns custom channels; `AddUserAsync` adds members | team/party/proximity channels |
| `TextChannel:SendAsync(text, metadata?)` | **client only** (LocalScript / client RunContext); only user-typed messages are delivered | the user's own messages |
| `TextChannel:DisplaySystemMessage(text)` | client | local system lines (hints, kill feed) — not filtered, so never put another player's text in it |
| `ShouldDeliverCallback(message, textSource)` | **server**, per receiving client | team-only / proximity / muted delivery; return truthy to deliver; the sender always sees their own message |
| `OnIncomingMessage` (channel or service) | client | decorate (prefix tags, colors); **must not yield**; on the sender it runs twice (sent locally, then filtered result) — not a one-shot trigger |
| `TextChatCommand` (`PrimaryAlias`, `SecondaryAlias`) under `TextChatService` | `Triggered(textSource, unfilteredText)` handled in a server Script | commands; the matching message is not replicated to others |
| `BubbleChatConfiguration`, `ChatWindowConfiguration`, `ChatInputBarConfiguration` | Studio/client | look and layout |
- `TextChatService.ChatVersion` is not writable by game scripts. Metadata on `SendAsync` is ≤ 200 characters.
- Players can turn on **Automatic Translations** (since 2026-06) even if the experience didn't; set
  `AutoLocalize = false` on labels that must stay literal (names, codes).

## Chat commands securely
`Triggered` gives you **unfiltered** text and a `TextSource` — an alias match is not authorization.
```luau
--!strict
-- Server Script. TextChatCommand "KickCommand" (PrimaryAlias "/kick") lives under TextChatService.
-- Authorization by UserId allowlist (or IsInGroupAsync/GetRolesInGroupAsync), never by name. TYPECHECKED only.
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local ADMINS: { [number]: true } = { [1234567] = true }
local kickCommand = TextChatService:WaitForChild("KickCommand") :: TextChatCommand

kickCommand.Triggered:Connect(function(textSource: TextSource, unfilteredText: string)
	local caller = Players:GetPlayerByUserId(textSource.UserId)
	if not caller or not ADMINS[caller.UserId] then
		return -- silently ignore: don't confirm that the command exists
	end
	local targetName = string.match(unfilteredText, "^%S+%s+(%S+)")
	if not targetName or #targetName > 20 then
		return
	end
	for _, player in Players:GetPlayers() do
		if string.lower(player.Name) == string.lower(targetName) and player ~= caller then
			player:Kick("Removed by a moderator")
			return
		end
	end
end)
```
- Never echo `unfilteredText` (or parts of it) to other players; if a command's argument must be shown (a team name,
  a sign text) filter it with `TextService:FilterStringAsync` and the right `GetNonChatStringFor…` method.
- Rate-limit commands that cost server work, like any remote.
- The default emote/mute commands come from `TextChatService.CreateDefaultCommands` (Studio property).

## Leaderboards
| Need | Approach |
|---|---|
| Live, per-server scores | `leaderstats` folder (server-owned `IntValue`s) or a custom UI fed by server attributes |
| Global top N | `OrderedDataStore` (integer values) → `GetSortedAsync(ascending, pageSize ≤ 100, min?, max?)` → `DataStorePages`; read `GetCurrentPage()`, `AdvanceToNextPageAsync()` only while needed |
| Friends leaderboard | `player:GetFriendsWhoPlayedAsync()` → user ids of friends who played this experience → `orderedStore:BatchGetAsync(keys)` |
- `BatchGetAsync` works **only on ordered stores** (standard stores throw); ≥ 1 key, default max 100 per call; each
  requested key costs one read from the ordered-store budget; missing keys are omitted from the result (result shape:
  `{ [key] = { value = n } }`).
- Writes: `SetAsync`/`UpdateAsync`/`IncrementAsync` on meaningful changes (session end, every few minutes for long
  sessions), coalesced per player — never on every kill. Refresh the displayed board on a timer (e.g. 60 s) from one
  server script and replicate it to clients; check `DataStoreService:GetRequestBudgetForRequestType` before bursts.
- Keys = `tostring(userId)`; values must be integers (store scores ×100 for two decimals). Ordered entries have no
  versions/metadata — keep the authoritative value in the player's profile, the ordered store is an index.

```luau
--!strict
-- Friend leaderboard fetch (server). TYPECHECKED only; budget-check and cache in real code.
local DataStoreService = game:GetService("DataStoreService")

local wins = DataStoreService:GetOrderedDataStore("Wins_v1")

type Row = { userId: number, wins: number }

local function friendScores(player: Player): { Row }
	local ok, friendIds = pcall(function()
		return player:GetFriendsWhoPlayedAsync()
	end)
	if not ok or #friendIds == 0 then
		return {}
	end
	local keys: { string } = { tostring(player.UserId) }
	for i, id in friendIds do
		if i > 99 then
			break -- one call: default max 100 keys
		end
		table.insert(keys, tostring(id))
	end
	local okBatch, entries = pcall(function()
		return wins:BatchGetAsync(keys)
	end)
	if not okBatch then
		return {}
	end
	local rows: { Row } = {}
	for key, entry in entries do
		local userId, value = tonumber(key), entry.value
		if userId and typeof(value) == "number" then
			table.insert(rows, { userId = userId, wins = value })
		end
	end
	table.sort(rows, function(a: Row, b: Row): boolean
		return a.wins > b.wins
	end)
	return rows
end

return friendScores
```

Sources: cd:chat/in-experience-text-chat, cd:chat/examples/custom-text-chat-commands, cd:chat/bubble-chat,
cd:reference/engine/classes/TextChatCommand, cd:reference/engine/classes/TextChannel,
cd:production/localization/automatic-translations, cd:players/leaderboards, cd:reference/engine/classes/OrderedDataStore,
cd:reference/engine/classes/GlobalDataStore, cd:reference/engine/classes/Player,
cd:cloud-services/data-stores/error-codes-and-limits, api:GlobalDataStore.BatchGetAsync,
api:Player.GetFriendsWhoPlayedAsync, api:TextChatCommand.Triggered.
