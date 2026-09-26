# Recipe: interaction system (ProximityPrompt + server validation + handler registry)

Evidence: code TYPECHECKED (luau-lsp strict, old + new solver, Roblox defs 0.740) · helpers CLI-EXECUTED ·
**not run in Studio**. Side: server (+ engine-provided prompt UI on clients).
Needs: `examples/lib` (Binder, TokenBucket, Validate, Cleanup). Used by: [door system](door-system.md),
[inventory & pickups](inventory.md). Chapters: [networking](../../handbook/roblox/03-networking.md),
[security](../../handbook/roblox/04-security.md), [UI/UX](../../handbook/roblox/18-ui-ux.md).

## What you get
Tag any Part/Model `Interactable` in Studio, set attributes, and it becomes usable: a prompt appears, the server
validates every trigger and dispatches to a handler chosen by the `InteractionType` attribute. No RemoteEvents are
needed — `ProximityPrompt.Triggered` already fires on the server with the triggering `Player`.

## Architecture
```text
Studio: object + tag "Interactable" + attributes ──► server Binder creates one ProximityPrompt per object
Client: engine shows prompt UI, handles keyboard/gamepad/touch + hold duration
Client presses ──► engine ──► server: prompt.Triggered(player)
Server onTriggered: rate limit → object enabled/cooldown → player alive → distance (server positions) →
                    optional line of sight → Handlers[InteractionType](ctx) → state change on server Instances
Clients react to replicated state (attributes/properties), e.g. DoorVisuals animates "Swing".
```
Why this shape:
- **Prompt = input device, not authority.** Exploiters can fire `Triggered` for any prompt they can see, from any
  distance, as fast as they like (they control their client). All checks happen on the server with server data.
- **Binder** (CollectionService tags) makes it work for objects that are cloned, destroyed or streamed; every prompt
  and connection is owned by a per-object `Cleanup`.
- **Registry** keeps the interaction core closed for modification: new behaviours are `Handlers.register("Door", fn)`
  in their own script. The core never grows a giant `if kind == ...` chain.
- **Attributes as the contract** (designer-editable in Studio, validated on read, never trusted blindly).

## Attribute contract
| Attribute | Type | Default | Meaning |
|---|---|---|---|
| `InteractionType` | string | — (required) | handler key: `Toggle`, `Pickup`, `Door`, your own |
| `ActionText` / `ObjectText` | string ≤ 64 | `Interact` / object name | prompt labels |
| `Distance` | number 1–50 | 10 | `MaxActivationDistance` |
| `HoldDuration` | number 0–10 | 0 | seconds to hold |
| `Cooldown` | number 0–60 | 0.25 | per-object cooldown (server) |
| `Enabled` | bool | true | server-controlled; false hides the prompt and rejects triggers |
| `RequireLineOfSight` | bool | false | server raycast from head to object (for through-wall abuse) |
| `ItemId` (Pickup) | string | — | item given by the `Pickup` handler |

## Code
Shared config (client-visible, no secrets):
<!-- code: examples/interaction/ReplicatedStorage/Interaction/Config.luau -->
```luau
-- file: examples/interaction/ReplicatedStorage/Interaction/Config.luau
--!strict
-- Shared interaction settings (client-visible: nothing secret here).
local Config = {
	TAG = "Interactable", -- CollectionService tag placed on Parts/Models in Studio
	DEFAULT_DISTANCE = 10, -- studs; per-object override: attribute Distance
	DISTANCE_SLACK = 4, -- server tolerance for latency/character size
	DEFAULT_COOLDOWN = 0.25, -- seconds per object; override: attribute Cooldown
	RATE = { capacity = 4, rate = 2 }, -- per-player interaction budget (burst, per second)
}
return table.freeze(Config)
```
<!-- /code -->

Handler registry with two built-ins (`Toggle`, `Pickup`) and integration hooks:
<!-- code: examples/interaction/ServerScriptService/Interaction/Handlers.luau -->
```luau
-- file: examples/interaction/ServerScriptService/Interaction/Handlers.luau
--!strict
-- Registry of interaction behaviours keyed by the target's "InteractionType" attribute.
-- Other systems register their own handlers (e.g. the door recipe registers "Door").
export type Context = {
	player: Player,
	character: Model,
	target: Instance,
	prompt: ProximityPrompt,
}
export type Handler = (ctx: Context) -> ()

local handlers: { [string]: Handler } = {}
local Handlers = {}

function Handlers.register(kind: string, handler: Handler)
	assert(handlers[kind] == nil, "duplicate interaction handler: " .. kind)
	handlers[kind] = handler
end

function Handlers.get(kind: string): Handler?
	return handlers[kind]
end

-- Built-in: flip a boolean "On" attribute (switches, lamps). Clients react to the attribute for visuals.
Handlers.register("Toggle", function(ctx: Context)
	ctx.target:SetAttribute("On", ctx.target:GetAttribute("On") ~= true)
end)

-- Integration hooks, replaced at startup by the game (InventoryServer wires them to the inventory).
Handlers.hasItem = function(_player: Player, _itemId: string): boolean
	return false
end

-- Built-in: one-shot pickup. `onPickup` is replaced by the game (e.g. inventory add) at startup.
Handlers.onPickup = function(player: Player, itemId: string): boolean
	print(player.Name, "picked up", itemId)
	return true
end

Handlers.register("Pickup", function(ctx: Context)
	local itemId = ctx.target:GetAttribute("ItemId")
	if type(itemId) ~= "string" then
		return
	end
	ctx.target:SetAttribute("Enabled", false) -- claim first: a second request in the same frame is rejected
	if Handlers.onPickup(ctx.player, itemId) then
		ctx.target:Destroy()
	else
		ctx.target:SetAttribute("Enabled", true) -- inventory full etc.
	end
end)

return Handlers
```
<!-- /code -->

Server core:
<!-- code: examples/interaction/ServerScriptService/InteractionServer.server.luau -->
```luau
-- file: examples/interaction/ServerScriptService/InteractionServer.server.luau
--!strict
-- Server-authoritative interactions via ProximityPrompts created for every tagged object.
-- The prompt is only an input device: the server re-checks rate, state, distance and (optionally) line of sight.
-- Requires: ReplicatedStorage.Lib (examples/lib), ReplicatedStorage.Interaction.Config, ServerScriptService.Interaction.Handlers.
-- Status: TYPECHECKED. Not run in Studio.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Binder = require(ReplicatedStorage.Lib.Binder)
local TokenBucket = require(ReplicatedStorage.Lib.TokenBucket)
local Validate = require(ReplicatedStorage.Lib.Validate)
local Config = require(ReplicatedStorage.Interaction.Config)
local Handlers = require(ServerScriptService.Interaction.Handlers)

local limiter = TokenBucket.new({ Interact = Config.RATE })
local nextAllowed: { [Instance]: number } = {}

local function attrNumber(inst: Instance, name: string, default: number, min: number, max: number): number
	return Validate.number(inst:GetAttribute(name), min, max) or default
end

local function attrString(inst: Instance, name: string, default: string): string
	return Validate.string(inst:GetAttribute(name), 64) or default
end

local function anchorPart(target: Instance): BasePart?
	if target:IsA("BasePart") then
		return target
	elseif target:IsA("Model") then
		return target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function hasLineOfSight(character: Model, from: Vector3, target: Instance, to: Vector3): boolean
	local params = RaycastParams.new()
	params.ExcludeInstances = { character }
	local hit = Workspace:Raycast(from, to - from, params)
	return hit == nil or hit.Instance == target or hit.Instance:IsDescendantOf(target)
end

local function onTriggered(prompt: ProximityPrompt, target: Instance, player: Player)
	local now = os.clock()
	-- 1. cheap checks first
	if not limiter:allow(player, "Interact", now) then
		return
	end
	if target:GetAttribute("Enabled") == false or now < (nextAllowed[target] or 0) then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	if not character or not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	-- 2. spatial checks with server-side positions (never client-reported ones)
	local part = anchorPart(target)
	if not part then
		return
	end
	local maxDistance = prompt.MaxActivationDistance + Config.DISTANCE_SLACK
	if (part.Position - root.Position).Magnitude > maxDistance then
		return
	end
	if target:GetAttribute("RequireLineOfSight") == true then
		local head = character:FindFirstChild("Head")
		local eye = if head and head:IsA("BasePart") then head.Position else root.Position
		if not hasLineOfSight(character, eye, target, part.Position) then
			return
		end
	end
	-- 3. dispatch
	local handler = Handlers.get(attrString(target, "InteractionType", ""))
	if not handler then
		return
	end
	nextAllowed[target] = now + attrNumber(target, "Cooldown", Config.DEFAULT_COOLDOWN, 0, 60)
	handler({ player = player, character = character, target = target, prompt = prompt })
end

Binder.bind(Config.TAG, function(target, cleanup)
	local part = anchorPart(target)
	if not part then
		warn("Interactable without a BasePart:", target:GetFullName())
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = attrString(target, "ActionText", "Interact")
	prompt.ObjectText = attrString(target, "ObjectText", target.Name)
	prompt.MaxActivationDistance = attrNumber(target, "Distance", Config.DEFAULT_DISTANCE, 1, 50)
	prompt.HoldDuration = attrNumber(target, "HoldDuration", 0, 0, 10)
	prompt.Enabled = target:GetAttribute("Enabled") ~= false
	prompt.Parent = part -- set properties first, parent last
	cleanup:add(prompt)
	cleanup:connect(prompt.Triggered, function(player: Player)
		onTriggered(prompt, target, player)
	end)
	cleanup:connect(target:GetAttributeChangedSignal("Enabled"), function()
		prompt.Enabled = target:GetAttribute("Enabled") ~= false
	end)
	cleanup:add(function()
		nextAllowed[target] = nil
	end)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	limiter:forget(player)
end)
```
<!-- /code -->

## Studio setup
1. Copy `examples/lib/ReplicatedStorage/Lib` → `ReplicatedStorage.Lib` (ModuleScripts), `Interaction/Config` →
   `ReplicatedStorage.Interaction.Config`, `Interaction/Handlers` → `ServerScriptService.Interaction.Handlers`,
   `InteractionServer.server.luau` → a `Script` in `ServerScriptService`. (Rojo users: the folders already map.)
2. Tag a Part `Interactable` (Tag Editor / Properties → Tags), add attribute `InteractionType = "Toggle"`.
3. For a Model, set `PrimaryPart` (the prompt anchors there; otherwise the first BasePart found).
4. Visual reaction for `Toggle`: a client script listens to `GetAttributeChangedSignal("On")` (lamp on/off).

## How to test (Studio → Test → Server & Clients, 2 players)
| # | Scenario | Expected |
|---|---|---|
| 1 | Walk up, press E on a Toggle | `On` flips once per press; both clients see it |
| 2 | Spam E | at most 4 quick triggers then ~2/s (token bucket); per-object cooldown respected |
| 3 | Two players press the same Pickup in the same frame | exactly one gets it (claim via `Enabled=false` first) |
| 4 | Object with `RequireLineOfSight`, stand behind a wall inside range | prompt may show (engine), server rejects |
| 5 | Destroy an Interactable at runtime / stream it out (StreamingEnabled, walk away) | prompt and connections cleaned; no errors |
| 6 | Die, respawn, interact | works; dead players rejected |
| 7 | Network simulator 250 ms | still works at the edge of range (DISTANCE_SLACK) |
Proving the server checks run (the engine may also refuse far triggers, which would hide a missing check):
temporarily set `Config.DISTANCE_SLACK = -9` → triggers near the edge of range must now be rejected; set a tiny
`RATE` → spam must be rejected; restore both. Add a temporary `print` in each early `return` while testing.

## Exploit checklist (what a hostile client does → why it fails)
| Attack | Defence in this code |
|---|---|
| Trigger from across the map | server distance vs `MaxActivationDistance + DISTANCE_SLACK` using server root position |
| Trigger through walls | `RequireLineOfSight` raycast (enable on valuables) |
| Flood triggers | TokenBucket per player (+ per-object cooldown) before any other work |
| Trigger while dead / no character | alive check |
| Double pickup race | handler claims (`Enabled=false`) before granting |
| Spoof InteractionType | attributes are server-owned; client edits don't replicate |

## Variations
- **Custom prompt UI**: set `prompt.Style = Enum.ProximityPromptStyle.Custom` and build UI on the client from
  `ProximityPromptService.PromptShown/PromptHidden` — logic stays identical.
- **Per-player visibility** (only the owner sees their loot): create the prompt on the client instead, and send a
  RemoteEvent intent to the server; the same validation applies (the object and distance checks move into the
  remote handler).
- **Hold with progress in the world**: `prompt.PromptButtonHoldBegan/Ended` on the client for VFX; server still
  acts only on `Triggered`.
- **Many (1000+) interactables**: prompts are cheap but not free; create prompts only for objects near players
  (server-side proximity binning) or rely on streaming to limit client work.

## Pitfalls
- `ProximityPrompt.Triggered` is also available on the client — don't run gameplay there.
- `prompt.RequiresLineOfSight` (engine) only affects prompt visibility, not server security.
- Don't parent the prompt before setting properties (extra replication, visible flicker).
- Handler errors: a failing handler must not break other interactions — each trigger runs in its own engine thread
  already; keep handlers short and non-yielding (or `task.spawn` long work).

Sources: cd:ui/proximity-prompts, cd:reference/engine/classes/ProximityPrompt,
cd:reference/engine/classes/ProximityPromptService, cd:reference/engine/classes/CollectionService,
cd:scripting/security/client-server-boundary, cd:workspace/raycasting, cd:scripting/attributes.
