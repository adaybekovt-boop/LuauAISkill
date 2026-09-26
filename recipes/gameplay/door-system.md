# Recipe: doors (server state + collision, client animation, locks, auto-close)

Evidence: TYPECHECKED · **not run in Studio**. Side: server (state/collision) + client (animation).
Needs: [interaction system](interaction-system.md), `examples/lib`. Keys come from [inventory](inventory.md)
through the `Handlers.hasItem` hook.

## Architecture
```text
Player triggers prompt → InteractionServer validates → Handlers["Door"]:
   locked? → has KeyItem? (Handlers.hasItem) → unlock, else set DeniedAt (clients rattle)
   open?   → doorway empty? → Swing = 0 + Blocker.CanCollide = true
   closed  → Swing = ±1 (away from the opener) + Blocker.CanCollide = false (+ AutoClose timer)
Every client: Binder("Door") reads Swing → animates Visual around Hinge locally (PreRender only while moving)
```
Key decisions:
- **Server never tweens.** Server-side TweenService replicates the property every frame and looks jittery under
  latency (creator-docs performance guidance: tween on the client). The server owns only the `Swing` attribute and
  the invisible `Blocker` collision.
- **Collision is a separate invisible part**, so the visual leaf can move smoothly on each client without
  server/client position fights. Trade-off: while swinging, the visual leaf doesn't push players.
- **Closing checks the doorway** (`GetPartsInPart` on the blocker) — closing collision onto a player traps or flings
  them.
- **Generation counter** invalidates stale auto-close timers when the door is toggled again.
- **Streaming-safe**: a door that streams in snaps to its current state (no animation replay); make door models
  `ModelStreamingMode = Atomic` so Hinge/Visual/Blocker arrive together.

## Door model (Studio)
```text
Door (Model)  Tags: Door, Interactable   Attributes: InteractionType="Door", [Locked, KeyItem, AutoClose, OpenAngle]
├─ Blocker (Part)  PrimaryPart · Anchored · CanCollide=true · Transparency=1 · covers the doorway
├─ Hinge   (Part)  Anchored · CanCollide=false · CanQuery=false · Transparency=1 · Y axis = swing axis,
│                  LookVector points out of the "front" side
└─ Visual  (Model) the leaf + handle · every part Anchored · CanCollide=false
```
Author the door **closed**. `OpenAngle` default 95°.

## Code
Server handler (registers into the interaction registry):
<!-- code: examples/interaction/ServerScriptService/Doors.server.luau -->
```luau
-- file: examples/interaction/ServerScriptService/Doors.server.luau
--!strict
-- Doors: server owns state + collision, clients animate the visual (see DoorVisuals.client.luau).
-- Door contract (set up in Studio):
--   Model tagged "Door" and "Interactable", attribute InteractionType = "Door"
--   ├─ Blocker (Part, PrimaryPart): invisible, Anchored, CanCollide — the only colliding part; prompt anchor
--   ├─ Hinge   (Part): invisible, Anchored, CanCollide=false; its CFrame is the swing axis (rotates around its Y)
--   └─ Visual  (Model): the door leaf, all parts Anchored, CanCollide=false (never moved by the server)
--   Attributes: Swing (number, replicated state: 0 closed, 1/-1 open away from the opener), Locked (bool),
--   KeyItem (string, inventory item that unlocks), AutoClose (seconds, 0 = never), DeniedAt (server time; set on
--   a locked attempt so clients can rattle the door).
-- Status: TYPECHECKED. Not run in Studio.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Binder = require(ReplicatedStorage.Lib.Binder)
local Validate = require(ReplicatedStorage.Lib.Validate)
local Handlers = require(ServerScriptService.Interaction.Handlers)

local DOOR_TAG = "Door"
local BLOCKED_RETRY = 1 -- seconds between auto-close attempts while someone stands in the doorway

local generation: { [Instance]: number } = {}

local function blockerOf(door: Instance): BasePart?
	local blocker = door:FindFirstChild("Blocker")
	return if blocker and blocker:IsA("BasePart") then blocker else nil
end

-- Closing on top of a character traps or flings them: only close when the doorway is empty.
local function doorwayOccupied(blocker: BasePart): boolean
	for _, part in Workspace:GetPartsInPart(blocker) do
		local model = part:FindFirstAncestorOfClass("Model")
		if model and model:FindFirstChildOfClass("Humanoid") then
			return true
		end
	end
	return false
end

local setSwing: (door: Instance, swing: number) -> ()

local function scheduleAutoClose(door: Instance, gen: number)
	local delaySeconds = Validate.number(door:GetAttribute("AutoClose"), 0, 600) or 0
	if delaySeconds <= 0 then
		return
	end
	local function attempt()
		if generation[door] ~= gen or door.Parent == nil then
			return -- door was toggled again or removed; this timer is stale
		end
		local blocker = blockerOf(door)
		if blocker and doorwayOccupied(blocker) then
			task.delay(BLOCKED_RETRY, attempt)
			return
		end
		setSwing(door, 0)
	end
	task.delay(delaySeconds, attempt)
end

setSwing = function(door: Instance, swing: number)
	local gen = (generation[door] or 0) + 1
	generation[door] = gen
	door:SetAttribute("Swing", swing)
	local blocker = blockerOf(door)
	if blocker then
		blocker.CanCollide = swing == 0
	end
	if swing ~= 0 then
		scheduleAutoClose(door, gen)
	end
end

Handlers.register("Door", function(ctx: Handlers.Context)
	local door = ctx.target
	if door:GetAttribute("Locked") == true then
		local key = door:GetAttribute("KeyItem")
		if type(key) ~= "string" or not Handlers.hasItem(ctx.player, key) then
			door:SetAttribute("DeniedAt", Workspace:GetServerTimeNow())
			return
		end
		door:SetAttribute("Locked", false) -- design choice: a key unlocks the door permanently
	end
	local current = door:GetAttribute("Swing")
	if current ~= nil and current ~= 0 then
		local blocker = blockerOf(door)
		if blocker and doorwayOccupied(blocker) then
			return -- refuse to close on someone
		end
		setSwing(door, 0)
		return
	end
	-- Swing away from the opener: which side of the hinge's look vector is the player on?
	local hinge = door:FindFirstChild("Hinge")
	local root = ctx.character:FindFirstChild("HumanoidRootPart")
	local side = 1
	if hinge and hinge:IsA("BasePart") and root and root:IsA("BasePart") then
		side = if (root.Position - hinge.Position):Dot(hinge.CFrame.LookVector) > 0 then -1 else 1
	end
	setSwing(door, side)
end)

Binder.bind(DOOR_TAG, function(door, cleanup)
	local swing = Validate.number(door:GetAttribute("Swing"), -1, 1) or 0
	door:SetAttribute("Swing", swing)
	local blocker = blockerOf(door)
	if blocker then
		blocker.CanCollide = swing == 0
	end
	cleanup:add(function()
		generation[door] = nil
	end)
end)
```
<!-- /code -->

Client animation:
<!-- code: examples/interaction/StarterPlayer/StarterPlayerScripts/DoorVisuals.client.luau -->
```luau
-- file: examples/interaction/StarterPlayer/StarterPlayerScripts/DoorVisuals.client.luau
--!strict
-- Client door animation. Reads the server-owned "Swing" attribute and rotates the door's Visual model around the
-- Hinge locally (official guidance: tween on clients, not the server — server tweens replicate every frame and
-- jitter). Streaming-safe: a door that streams in applies its current state instantly.
-- Status: TYPECHECKED. Not run in Studio.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Binder = require(ReplicatedStorage.Lib.Binder)

local OPEN_TIME = 0.55
local DEFAULT_ANGLE = 95 -- degrees; per-door override: attribute OpenAngle
local RATTLE_TIME = 0.25

type Anim = {
	visual: Model,
	hinge: CFrame,
	offset: CFrame, -- visual pivot relative to the hinge when closed
	angle: number, -- current radians
	from: number,
	to: number,
	t: number,
	duration: number,
	rattle: number, -- seconds of rattle left
}

local animating: { [Anim]: true } = {}
local stepConnection: RBXScriptConnection? = nil

local function apply(a: Anim, extra: number)
	a.visual:PivotTo(a.hinge * CFrame.Angles(0, a.angle + extra, 0) * a.offset)
end

local function step(dt: number)
	for a in animating do
		a.t = math.min(a.t + dt, a.duration)
		local alpha = TweenService:GetValue(a.t / a.duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		a.angle = a.from + (a.to - a.from) * alpha
		local extra = 0
		if a.rattle > 0 then
			a.rattle = math.max(0, a.rattle - dt)
			extra = math.rad(1.5) * math.sin(a.rattle * 60) * (a.rattle / RATTLE_TIME)
		end
		apply(a, extra)
		if a.t >= a.duration and a.rattle <= 0 then
			animating[a] = nil
		end
	end
	if next(animating) == nil and stepConnection then
		stepConnection:Disconnect() -- no per-frame cost while every door is idle
		stepConnection = nil
	end
end

local function start(a: Anim)
	animating[a] = true
	if not stepConnection then
		stepConnection = RunService.PreRender:Connect(step)
	end
end

local function targetAngle(door: Instance): number
	local swing = door:GetAttribute("Swing")
	local degrees = door:GetAttribute("OpenAngle")
	local open = if type(degrees) == "number" and degrees == degrees then math.clamp(degrees, 0, 180) else DEFAULT_ANGLE
	return if type(swing) == "number" then math.rad(open) * math.clamp(swing, -1, 1) else 0
end

Binder.bind("Door", function(door, cleanup)
	local visual = door:FindFirstChild("Visual")
	local hingePart = door:FindFirstChild("Hinge")
	if not (visual and visual:IsA("Model") and hingePart and hingePart:IsA("BasePart")) then
		warn("Door is missing Visual (Model) or Hinge (Part):", door:GetFullName())
		return
	end
	local a: Anim = {
		visual = visual,
		hinge = hingePart.CFrame,
		offset = hingePart.CFrame:ToObjectSpace(visual:GetPivot()),
		angle = 0,
		from = 0,
		to = 0,
		t = 0,
		duration = OPEN_TIME,
		rattle = 0,
	}
	-- NOTE: `offset` assumes the door is authored closed in Studio (the server never moves the Visual).
	a.angle = targetAngle(door)
	a.to = a.angle
	apply(a, 0) -- streamed-in or late-joining clients snap to the current state

	cleanup:connect(door:GetAttributeChangedSignal("Swing"), function()
		a.from, a.to, a.t = a.angle, targetAngle(door), 0
		start(a)
	end)
	cleanup:connect(door:GetAttributeChangedSignal("DeniedAt"), function()
		a.rattle = RATTLE_TIME
		a.from, a.to, a.t = a.angle, a.angle, a.duration
		start(a)
	end)
	cleanup:add(function()
		animating[a] = nil
	end)
end)
```
<!-- /code -->

## How to test (Server & Clients, 2 players)
| # | Scenario | Expected |
|---|---|---|
| 1 | Open from the front, then from the back | swings away from the opener each time |
| 2 | Stand in the doorway, press E to close / wait for AutoClose | refuses to close; auto-close retries every 1 s |
| 3 | Locked door without key | rattle on both clients, stays closed; with `Keycard` in inventory: unlocks and opens |
| 4 | Toggle rapidly | limited by rate limit + cooldown; no stale auto-close slams it shut early |
| 5 | Player 2 joins while door is open / streams in later | door already open, no animation replay |
| 6 | 30 doors idle | no per-frame script cost (MicroProfiler: no PreRender work from DoorVisuals) |

## Variations
- **Sliding door**: same pattern; client lerps `Visual` pivot along the Hinge's RightVector instead of rotating.
- **Double doors**: two Visual models, one rotating `+angle`, the other `-angle`; one Blocker.
- **Door sounds**: play client-side on `Swing` change (Audio API emitter on the Hinge); locked rattle on `DeniedAt`.
- **Physics doors** (HingeConstraint, pushable): only for non-critical props; network ownership makes them
  exploitable and jittery — keep gameplay doors anchored.
- **NPC-usable doors**: NPC code calls the same `setSwing` logic via a server module instead of a prompt;
  pathfinding treats a closed door as passable only if the NPC can open it (`PathfindingModifier` label).

## Pitfalls
- Moving the Hinge or the whole door at runtime (procedural placement) after the client bound it: re-bind (remove and
  re-add the tag) so the client recomputes its offsets.
- Don't weld the Visual to anything unanchored — the leaf must be anchored or physics will drop it.
- `CanCollide=false` Visual parts still block raycasts (`CanQuery`); set `CanQuery=false` on the leaf if bullets
  should use the Blocker instead.

Sources: cd:performance-optimization/improve, cd:workspace/streaming/techniques, cd:workspace/collisions,
cd:reference/engine/classes/TweenService, cd:reference/engine/classes/WorldRoot, cd:ui/proximity-prompts.
