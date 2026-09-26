# Recipe: remotes with rate limits and parsers (NetServer / NetClient)

Evidence: TokenBucket CLI-EXECUTED (`examples/tests/lib.spec.luau`) · NetServer/NetClient/examples TYPECHECKED ·
**not run in Studio**. Side: server declares, client consumes.
Chapters: [networking](../../handbook/roblox/03-networking.md), [security](../../handbook/roblox/04-security.md).

## What problem it solves
Every client→server remote needs the same three things in the same order: **rate limit → parse/validate →
handle**. Written by hand in every handler they get skipped or reordered. `NetServer` declares a remote together
with its limit and parser, so a handler can only ever receive validated data. It's ~150 lines, not a framework.

## Architecture
```text
Server startup: NetServer.event(name, {limit, parse}, handler[, unreliable]) → creates Remotes/<name>
Client:         NetClient.sender(name, limit)(args...)  → local throttle (UX) → FireServer
Server:         OnServerEvent(player, ...) → TokenBucket(player, name) → parse(...) → handler(player, parsed)
                rejections: silent to client, counted (NetServer.stats), repeated garbage → NetServer.onAbuse
Requests:       NetServer.request(...) ↔ NetClient.request(name, timeout, ...) (client never hangs)
```
Decisions:
- **Per-player, per-remote token buckets** (burst + sustained). Keys are Player objects and fixed remote names —
  never client-supplied strings (memory exhaustion).
- **Parser returns a typed value or nil.** Validation is data-shaped (`Validate.number/integer/oneOf/...`);
  NaN/inf/huge strings/wrong types all fail.
- **Silent rejection** (no error reply) avoids giving exploiters an oracle; counters give you monitoring.
- **No auto-kick on rate limits**: lag spikes deliver legitimate bursts. Kick/ban decisions belong to a human-tuned
  policy in `onAbuse`, driven by invalid payloads (which honest clients never send).
- **Client throttle** keeps honest clients far below server limits (send-on-change, ≤ 15–20 Hz streams).

## Code
<!-- code: examples/net/ServerScriptService/Net/NetServer.luau -->
```luau
-- file: examples/net/ServerScriptService/Net/NetServer.luau
--!strict
-- NetServer: declare each remote once with a rate limit and a parser; handlers only ever see parsed, typed data.
-- Not a framework — ~120 lines you can read in one go. Order per message: rate limit → parse → handler.
-- Rejections are silent to the client (no oracle for exploiters) but counted for monitoring.
-- Status: TYPECHECKED. Not run in Studio.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TokenBucket = require(ReplicatedStorage.Lib.TokenBucket)

export type Limit = TokenBucket.Limit
export type Spec<T> = {
	limit: Limit, -- per player: burst `capacity`, sustained `rate` per second
	parse: (...unknown) -> T?, -- validate + convert raw args; nil = reject
}
type Counters = { accepted: number, limited: number, invalid: number }

local NetServer = {}

-- Called when a player keeps sending garbage (default: log). Don't auto-kick on rate limits alone:
-- lag spikes deliver bursts of legitimate messages.
NetServer.onAbuse = function(player: Player, remote: string, invalidPerMinute: number)
	warn(`[Net] {player.Name} ({player.UserId}) sent {invalidPerMinute} invalid {remote} messages in a minute`)
end
NetServer.ABUSE_THRESHOLD = 30

local folder: Folder? = nil
local counters: { [string]: Counters } = {}
local invalidByPlayer: { [Player]: number } = {}
local forgetters: { (Player) -> () } = {}

local function getFolder(): Folder
	if folder then
		return folder
	end
	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	local f = if existing and existing:IsA("Folder") then existing else Instance.new("Folder")
	f.Name = "Remotes"
	f.Parent = ReplicatedStorage
	folder = f
	return f
end

-- RemoteEvent and UnreliableRemoteEvent share an API but no scriptable base type; create either as Instance.
local function newEvent(name: string, unreliable: boolean?): Instance
	local remote = Instance.new(if unreliable then "UnreliableRemoteEvent" else "RemoteEvent")
	remote.Name = name
	remote.Parent = getFolder()
	return remote
end

local function track(name: string, limit: Limit): (Player) -> "ok" | "limited"
	assert(counters[name] == nil, "remote declared twice: " .. name)
	counters[name] = { accepted = 0, limited = 0, invalid = 0 }
	local limiter = TokenBucket.new({ [name] = limit })
	table.insert(forgetters, function(player: Player)
		limiter:forget(player)
	end)
	return function(player: Player)
		if limiter:allow(player, name, os.clock()) then
			return "ok"
		end
		counters[name].limited += 1
		return "limited"
	end
end

local function invalid(player: Player, name: string)
	counters[name].invalid += 1
	local n = (invalidByPlayer[player] or 0) + 1
	invalidByPlayer[player] = n
	if n == NetServer.ABUSE_THRESHOLD then
		NetServer.onAbuse(player, name, n)
	end
end

-- Client → server event. `unreliable = true` for continuous cosmetic data (≤ 1000 bytes, may drop/reorder).
function NetServer.event<T>(name: string, spec: Spec<T>, handler: (Player, T) -> (), unreliable: boolean?): Instance
	local remote = newEvent(name, unreliable)
	local gate = track(name, spec.limit)
	local signal = (remote :: any).OnServerEvent :: RBXScriptSignal
	signal:Connect(function(player: Player, ...: unknown)
		if gate(player) ~= "ok" then
			return
		end
		local parsed = spec.parse(...)
		if parsed == nil then
			invalid(player, name)
			return
		end
		counters[name].accepted += 1
		handler(player, parsed)
	end)
	return remote
end

-- Client → server request/response. The handler must not yield for long (the client waits); returning nil tells
-- the client "rejected/failed" — clients must handle nil and time out their UI.
function NetServer.request<T>(name: string, spec: Spec<T>, handler: (Player, T) -> any): RemoteFunction
	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = getFolder()
	local gate = track(name, spec.limit)
	remote.OnServerInvoke = function(player: Player, ...: unknown): any
		if gate(player) ~= "ok" then
			return nil
		end
		local parsed = spec.parse(...)
		if parsed == nil then
			invalid(player, name)
			return nil
		end
		counters[name].accepted += 1
		return handler(player, parsed)
	end
	return remote
end

-- Server → client remote (no limiter needed; the server is trusted). Declared here so all remotes live in one folder.
function NetServer.broadcast(name: string, unreliable: boolean?): Instance
	return newEvent(name, unreliable)
end

function NetServer.stats(): { [string]: Counters }
	return table.clone(counters)
end

Players.PlayerRemoving:Connect(function(player: Player)
	invalidByPlayer[player] = nil
	for _, forget in forgetters do
		forget(player)
	end
end)

-- Abuse counters are per minute.
task.spawn(function()
	while true do
		task.wait(60)
		table.clear(invalidByPlayer)
	end
end)

return NetServer
```
<!-- /code -->

<!-- code: examples/net/ReplicatedStorage/Net/NetClient.luau -->
```luau
-- file: examples/net/ReplicatedStorage/Net/NetClient.luau
--!strict
-- NetClient: find server-created remotes (with timeouts) and throttle sends locally so normal play never hits the
-- server's limits. Client throttling is UX only — the server enforces the real limits.
-- Status: TYPECHECKED. Not run in Studio.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TokenBucket = require(ReplicatedStorage.Lib.TokenBucket)

local NetClient = {}
local TIMEOUT = 15

local function folder(): Instance
	local f = ReplicatedStorage:WaitForChild("Remotes", TIMEOUT)
	assert(f, "ReplicatedStorage.Remotes not found (server scripts not running?)")
	return f
end

function NetClient.remote(name: string): Instance
	local r = folder():WaitForChild(name, TIMEOUT)
	assert(r, "remote not found: " .. name)
	return r
end

-- Returns fire(...) that sends at most `limit` (burst/rate) and silently drops the excess.
-- For continuous data (aim, look) drop is correct: the next update supersedes it.
function NetClient.sender(name: string, limit: TokenBucket.Limit): (...any) -> boolean
	local remote = NetClient.remote(name)
	local bucket = TokenBucket.new({ send = limit })
	return function(...: any): boolean
		if not bucket:allow("self", "send", os.clock()) then
			return false
		end
		if remote:IsA("RemoteEvent") then
			remote:FireServer(...)
		elseif remote:IsA("UnreliableRemoteEvent") then
			remote:FireServer(...)
		end
		return true
	end
end

-- InvokeServer with a client-side timeout: resolves to nil if the server doesn't answer in `timeout` seconds.
function NetClient.request(name: string, timeout: number, ...: any): any
	local remote = NetClient.remote(name) :: RemoteFunction
	local result: any = nil
	local done = false
	local args = table.pack(...)
	local thread = coroutine.running()
	task.spawn(function()
		local ok, value = pcall(remote.InvokeServer, remote, table.unpack(args, 1, args.n))
		if not done then
			done = true
			result = if ok then value else nil
			task.spawn(thread)
		end
	end)
	task.delay(timeout, function()
		if not done then
			done = true
			task.spawn(thread)
		end
	end)
	coroutine.yield()
	return result
end

return NetClient
```
<!-- /code -->

Usage — three typical remotes:
<!-- code: examples/net/ServerScriptService/NetExample.server.luau -->
```luau
-- file: examples/net/ServerScriptService/NetExample.server.luau
--!strict
-- Three typical remotes declared with NetServer: a discrete action, a continuous cosmetic stream, a request.
-- Status: TYPECHECKED. Not run in Studio.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Validate = require(ReplicatedStorage.Lib.Validate)
local NetServer = require(ServerScriptService.Net.NetServer)

local EMOTES: { [string]: boolean } = { Wave = true, Point = true, Cheer = true }
local SHOP = { "Flashlight", "Battery", "Bandage", "Keycard", "Glowstick", "Map" }
local PAGE_SIZE = 4

-- 1. Discrete action (reliable): a few per burst, one every 2 s sustained.
NetServer.event("RequestEmote", {
	limit = { capacity = 3, rate = 0.5 },
	parse = function(emote: unknown): string?
		return Validate.oneOf(emote, EMOTES)
	end,
}, function(player: Player, emote: string)
	local character = player.Character
	if character then
		character:SetAttribute("Emote", emote) -- replicated state; clients play the animation
	end
end)

-- 2. Continuous cosmetic stream (unreliable): head pitch for other players' views, ≤ 20 Hz.
local aimRelay = NetServer.broadcast("AimPitchRelay", true)
NetServer.event("AimPitch", {
	limit = { capacity = 25, rate = 20 },
	parse = function(pitch: unknown): number?
		return Validate.number(pitch, -80, 80) -- degrees; also rejects NaN/inf
	end,
}, function(player: Player, pitch: number)
	-- Quantize: 0.5° steps are invisible and keep the payload tiny.
	(aimRelay :: UnreliableRemoteEvent):FireAllClients(player.UserId, math.round(pitch * 2) / 2)
end, true)

-- 3. Request/response: shop page. Non-yielding handler; returns a fresh table (never internal state).
NetServer.request("GetShopPage", {
	limit = { capacity = 5, rate = 1 },
	parse = function(page: unknown): number?
		return Validate.integer(page, 1, math.ceil(#SHOP / PAGE_SIZE))
	end,
}, function(_player: Player, page: number)
	local items = {}
	for i = (page - 1) * PAGE_SIZE + 1, math.min(page * PAGE_SIZE, #SHOP) do
		table.insert(items, SHOP[i])
	end
	return items
end)
```
<!-- /code -->

<!-- code: examples/net/StarterPlayer/StarterPlayerScripts/NetExample.client.luau -->
```luau
-- file: examples/net/StarterPlayer/StarterPlayerScripts/NetExample.client.luau
--!strict
-- Client side of NetExample: sends camera pitch only when it changed noticeably, capped at 15 Hz.
-- Status: TYPECHECKED. Not run in Studio.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local NetClient = require(ReplicatedStorage.Net.NetClient)

local sendPitch = NetClient.sender("AimPitch", { capacity = 3, rate = 15 })
local lastSent = math.huge

RunService.PreRender:Connect(function()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local look = camera.CFrame.LookVector
	local pitch = math.deg(math.asin(math.clamp(look.Y, -1, 1)))
	if math.abs(pitch - lastSent) >= 1 and sendPitch(pitch) then -- send on change, not every frame
		lastSent = pitch
	end
end)

local page = NetClient.request("GetShopPage", 5, 1)
print("shop page 1:", page) -- nil means rejected or timed out: show a retry button, never hang the UI
```
<!-- /code -->

## Choosing limits
| Message kind | Example | Burst / rate | Transport |
|---|---|---|---|
| discrete, rare | emote, buy, craft | 3 / 0.5–1 per s | RemoteEvent |
| gameplay action | fire weapon | weapon RPM/60 + small tolerance | RemoteEvent (+ server cooldown) |
| continuous cosmetic | aim pitch, look dir | 20–30 / 15–20 per s | UnreliableRemoteEvent, ≤ 1000 bytes |
| request/response | shop page, leaderboard page | 5 / 1 per s | RemoteFunction (server handler non-yielding) |
Budget reality: ≈500 requests/s per client is the engine cap across all remotes of a type; design normal play for
≤ 20–30 messages/s per client in total.

## How to test
- CLI: `luau examples/tests/lib.spec.luau` (bucket burst/refill, unknown actions, NaN time/cost, clock going
  backwards).
- Studio (Server & Clients): temporary client script firing `RequestEmote` 50× in a loop → 3 accepted then ~1 per 2 s;
  `FireServer("AimPitch", 0/0)` / `("AimPitch", "x")` → rejected, `NetServer.stats()` invalid counter rises; 30 invalid
  → one `onAbuse` warning.
- Network simulator (250 ms, jitter): honest play never trips limits (check `limited` counter stays ~0).

## Pitfalls
- The limiter doesn't replace game-state checks (cooldowns, ammo, alive) — those live in handlers.
- Don't use one generic `Network` remote with a string command unless every command still gets its own limit and
  parser; the per-remote form makes MicroProfiler/Network stats readable.
- `RemoteFunction:InvokeClient` is never used here — the server must not wait on clients.
- Remotes must be created by the server; client-created remotes don't replicate.

Sources: cd:scripting/events/remote, cd:reference/engine/classes/RemoteEvent,
cd:reference/engine/classes/UnreliableRemoteEvent, cd:reference/engine/classes/RemoteFunction,
cd:scripting/security/security-tactics, cd:studio/network-simulator.
