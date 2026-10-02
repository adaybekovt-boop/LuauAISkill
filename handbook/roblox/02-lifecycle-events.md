# Lifecycle: players, characters, tagged objects, attributes, cleanup

## TL;DR
- Handle existing players and future player arrivals.
- Separate player lifetime from character lifetime.
- Use binders for tagged objects and undo their work on removal.
- Treat streamed instances as temporary on clients.
- Disconnect connections and destroy owned resources explicitly.

Read when: code that runs per player / per character / per tagged object; respawn bugs; leaks; "works for the
first player only". Related: [async](../luau/05-coroutines-task-errors.md), [streaming](10-streaming.md),
[code quality](22-code-quality.md).

## Canonical per-player / per-character pattern (server or client)
```luau
--!strict
local Players = game:GetService("Players")

local function onCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then return end
	local conns: { RBXScriptConnection } = {}
	table.insert(conns, humanoid.Died:Connect(function()
		print(player.Name, "died")
	end))
	-- Everything owned by this character is released when the character is removed/destroyed.
	character.Destroying:Once(function()
		for _, c in conns do c:Disconnect() end
	end)
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function(character) onCharacter(player, character) end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character) -- character may exist before we connected
	end
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do           -- players who joined before this script ran
	task.spawn(onPlayer, player)
end
Players.PlayerRemoving:Connect(function(player: Player)
	-- release per-player state here (tables keyed by player, rate limiters, profiles)
	print("bye", player.UserId)
end)
```
Why each line matters:
- Iterate `GetPlayers()` after connecting `PlayerAdded`: in Studio play-solo and on fast servers a player can join
  before your script connects.
- Handle an existing `player.Character`: `CharacterAdded` may have fired already.
- `WaitForChild` with a timeout: never an infinite wait on something that may never arrive (streaming, custom rigs).
- Each respawn creates a **new** character model. `Workspace.PlayerCharacterDestroyBehavior` (Studio setting):
  `Enabled` makes the engine `Destroy()` old characters on respawn and `Player` objects on leave (frees their
  connections — recommended); `Default` = engine default. Never keep using an old character reference.

Client version: use `Players.LocalPlayer` and the same `CharacterAdded` + existing-character handling.
`StarterCharacterScripts` copies run once per character automatically (script lifetime = character lifetime).

## Character facts
- Default character: Humanoid + `HumanoidRootPart` (the assembly root) + R15/R6 limbs; `Humanoid.RootPart`.
- `player.CharacterAppearanceLoaded` fires after accessories/clothing load (for thumbnails, not gameplay start).
- `Humanoid.Died` fires once; `Humanoid.HealthChanged`, `StateChanged`, `Running`, `Jumping`, `FreeFalling`.
- Respawn: `Players.RespawnTime`, `Players.CharacterAutoLoads` (set false for custom spawn flow, then call
  `player:LoadCharacterAsync()` — `LoadCharacter` is deprecated).
- `StarterGui` ScreenGuis with `ResetOnSpawn = true` (default) are re-cloned every respawn → scripts inside restart
  and lose state. Set `ResetOnSpawn = false` for persistent HUDs and handle character changes yourself.
- Server moves characters with `character:PivotTo(cf)` (not `SetPrimaryPartCFrame`, deprecated).

## Tagged objects: CollectionService binder (replaces scripts inside every model)
```luau
--!strict
local CollectionService = game:GetService("CollectionService")

type Cleanup = () -> ()
local function bindTag(tag: string, setup: (Instance) -> Cleanup?)
	local active: { [Instance]: Cleanup } = {}
	local function add(inst: Instance)
		if active[inst] then return end            -- idempotent: streaming can re-add
		local cleanup = setup(inst)
		active[inst] = cleanup or function() end
	end
	local function remove(inst: Instance)
		local cleanup = active[inst]
		if cleanup then
			active[inst] = nil
			cleanup()
		end
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(remove)
	for _, inst in CollectionService:GetTagged(tag) do
		task.spawn(add, inst)
	end
end

bindTag("SpinningFan", function(inst)
	if not inst:IsA("BasePart") then return nil end
	local attachment = Instance.new("Attachment")
	attachment.Parent = inst
	return function() attachment:Destroy() end
end)
```
- Tags: `inst:AddTag("X")`, `inst:HasTag("X")`, `inst:RemoveTag("X")`, `inst:GetTags()` (Instance methods) or the
  `CollectionService` equivalents. Tags replicate. Removing an Instance from the DataModel (including stream-out)
  fires the removed signal; re-parenting fires added again → bindings must be idempotent.
- On the client with streaming, tagged objects appear/disappear as the player moves — the binder above is the
  correct pattern ([streaming](10-streaming.md)).

## Attributes: replicated custom properties
- `inst:SetAttribute(name, value)` / `GetAttribute` / `GetAttributes()` / `GetAttributeChangedSignal(name)` /
  `AttributeChanged`. Types: string, boolean, number, UDim, UDim2, BrickColor, Color3, Vector2, Vector3, CFrame,
  NumberSequence, ColorSequence, NumberRange, Rect, Font. Not tables, not Instances.
- Server-set attributes replicate to clients; client-set attributes stay local. Use them for small replicated
  state (door `Open`, NPC `State`, item `Rarity`) that clients render.
- Server-authority mode adds limits (first 64 attributes, name ≤ 50 chars, string ≤ 50 chars replicate)
  ([05](05-server-authority.md)).
- Don't store secrets or large data in attributes; don't spam changes every frame (each change replicates).

## Value objects vs attributes vs remotes
| Need | Use |
|---|---|
| Small replicated state on an object | attribute |
| Replicated state that must reference an Instance | `ObjectValue` (attributes can't hold Instances) |
| One-off notification ("you got a kill") | `RemoteEvent` |
| Continuous cosmetic stream (aim direction) | `UnreliableRemoteEvent` |
| Per-player private data | remote to that player only (attributes on `Player` replicate to **all** clients) |

## Destroying and cleanup rules
- `inst:Destroy()` sets Parent to nil, locks Parent, disconnects all connections **on that Instance and its
  descendants**, and destroys descendants. Your Lua references keep the object alive in memory until dropped.
- Connections to other objects (services, other models, `RunService`) survive — disconnect them explicitly.
- Use `Instance.Destroying` to run cleanup when something is destroyed; under deferred signals it runs *after*
  destruction (don't expect children/parent to still be intact).
- Temporary objects: `Debris:AddItem(inst, seconds)` works but can't be cancelled; prefer `task.delay` with an owner
  check, or pool.

## Common lifecycle bugs
| Symptom | Cause | Fix |
|---|---|---|
| Works for first life only | connected to old character/humanoid | re-bind in `CharacterAdded`; use `StarterCharacterScripts` |
| HUD resets on death | `ScreenGui.ResetOnSpawn = true` | set false; re-bind to new humanoid |
| Handler runs twice | duplicate entry scripts, or starter-container client Script cloned | one entrypoint; LocalScript in starter containers |
| Memory grows per join | per-player tables not cleared | clear on `PlayerRemoving` |
| Nil errors on join in Studio | player joined before connect | iterate `GetPlayers()` |
| Error "attempt to index nil with Humanoid" after respawn | cached `character` from previous life | fetch fresh from `player.Character` |

Sources: cd:players/index, cd:characters/index, cd:reference/engine/classes/Players, cd:reference/engine/classes/Player,
cd:reference/engine/classes/CollectionService, cd:scripting/attributes, cd:studio/properties, cd:scripting/events/deferred,
cd:reference/engine/classes/Instance, cd:projects/server-authority/index.
