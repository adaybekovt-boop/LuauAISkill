# Character controllers: walking, sprint, crouch, slide, vault, ladders, footsteps, fall damage

Read when: movement features, first-person feel, stamina, parkour.
Related: [camera](14-camera.md), [animation](16-animation.md), [security](04-security.md#movement-and-physics-ownership),
recipes [sprint/crouch/stamina](../../recipes/gameplay/sprint-crouch-stamina.md), [footsteps](../../recipes/gameplay/footsteps.md).

## Choose the controller
| Option | Status | Use when |
|---|---|---|
| **Humanoid** (default) | stable | almost everything; well understood; animations/tools/seats work |
| Humanoid + custom logic (WalkSpeed, states, forces) | stable | sprint/crouch/slide/vault/lean on top of Humanoid (this chapter) |
| `ControllerManager` + `GroundController`/`AirController`/`ClimbController`/`SwimController` + sensors | stable API, physics-based | custom physical characters, vehicles-like creatures; more work |
| Character Controller Library (CCL, `require("@rbx/AvatarAbilities")`) | **beta** (File → Beta Features → "AvatarAbilities Character Controller Library", Avatar Settings → Movement) | prototyping ability systems (labels, conditions, conflicts); don't ship without checking release status |
| Fully custom (anchored root + CFrame) | stable | top-down/2D games, NPC crowds; you own collisions |

## Humanoid essentials
- `WalkSpeed` (default 16 studs/s), `JumpHeight` (7.2) or `JumpPower` (50) depending on `UseJumpPower`,
  `HipHeight`, `MaxSlopeAngle` (default 89°), `AutoRotate`, `MoveDirection` (world-space input direction, read-only),
  `FloorMaterial` (Material under feet, `Air` when airborne), `RootPart`.
- States: `Humanoid.StateChanged(old, new)`; `Enum.HumanoidStateType` Running, Jumping, Freefall, Landed, Climbing,
  Swimming, Seated, Physics, Ragdoll, FallingDown, GettingUp, Dead, PlatformStanding, StrafingNoPhysics...
  `Humanoid:SetStateEnabled(state, false)` disables transitions into it (do it on the machine that owns the
  character — the client for players). `ChangeState` forces a state (owner side).
- `Humanoid:Move(direction, relativeToCamera)` drives movement from code; `Humanoid:MoveTo(pos)` walks to a point
  (times out after 8 s unless re-issued; `MoveToFinished(reached)`).
- Player characters are **client-owned**: movement feel must be implemented on the client for responsiveness;
  the server validates/limits (speed checks, stamina authority).

## Authority pattern for movement abilities
```text
Client: input → start ability locally (WalkSpeed, animation, camera) → FireServer("Sprint", true)
Server: validate (alive, not stunned, stamina > threshold, rate) → record state + start stamina drain
        → if invalid or stamina empty: FireClient("ForceStop", ...) and speed validator stops tolerating sprint speed
Server speed validator: allowed speed = base or sprint speed (only while server thinks sprinting) + tolerance
```
Client-set `WalkSpeed` is local; the server should not trust it but can't read it either — validate displacement.

## Feature recipes (key decisions)
| Feature | Implementation | Pitfalls |
|---|---|---|
| **Sprint** | WalkSpeed 16→24–26, FOV +5–8 (tween 0.15 s), stamina drain server-side; only while moving forward-ish (`MoveDirection:Dot(lookVector) > 0.5`) | restore on death/respawn; stop when stamina 0; debounce toggle vs hold per settings |
| **Stamina** | server authoritative number, regen after delay (1–1.5 s); client predicts for UI | don't replicate every frame — send on start/stop + periodic correction (2–4 Hz) |
| **Crouch** | lower `HipHeight`/play crouch anim, WalkSpeed ~8, camera offset −1.5; stand only if upward `Blockcast` from root finds no ceiling | R15 collision comes from body parts; test low vents; crouch-jump rules |
| **Slide** | from sprint: impulse/`LinearVelocity` along forward on the ground, decay over 0.6–0.9 s, lower camera, cooldown | slopes accelerate; stop on wall hit (raycast ahead); server tolerance for burst speed |
| **Jump/land** | detect `Landed` state; landing camera dip proportional to fall speed | double-landing events; ignore tiny drops |
| **Fall damage** | on `Freefall` start record Y (or use `AssemblyLinearVelocity.Y` at `Landed`); damage = f(fall height beyond threshold, e.g. > 20 studs) applied **by the server** (server can observe the character's state/velocity which replicate from the owner) | exploiters can cancel their own fall; water/trampolines exempt |
| **Ladder** | simplest: TrussPart or ladder geometry Humanoid can climb (rungs); custom: climb volume → `LinearVelocity` along ladder axis while in zone, disable when leaving | Humanoid climbing is picky about rung spacing |
| **Vault / mantle** | 3 raycasts forward (knee, chest, head) + one down from above the obstacle to find top & height; if knee hit & head clear & height ≤ max: play animation and move root along a curve over 0.3–0.5 s (client), with collisions allowed on the path check | never teleport through walls: validate target space with `Blockcast`/`GetPartBoundsInBox`; server movement validator must allow vault bursts |
| **Lean** | camera offset + roll ≤ 10–15°, upper-torso animation; for PvP, send lean state to the server (hitbox/peek fairness) | motion sickness; collision of camera with walls |
| **Footsteps** | stride-distance based, material table from `FloorMaterial`, play on each character locally (see below) | time-based loops desync with speed |
| **Head bob / sway** | driven by stride phase and velocity, spring-damped, reduced-motion toggle ([camera](14-camera.md)) | pure `sin(time)` bob feels fake and nauseating |

## Stride-based footsteps (client, for every visible character)
```luau
--!strict
local RunService = game:GetService("RunService")
local STRIDE = 5.5                      -- studs per step at walk; scale with speed if desired
local distanceAcc: { [Humanoid]: number } = {}

local function stepSound(humanoid: Humanoid, material: Enum.Material)
	-- pick from a material table; randomize sample + pitch 0.9–1.1; volume by speed
	print(humanoid.Parent, "step on", material.Name)
end

RunService.PostSimulation:Connect(function(dt: number)
	for humanoid, acc in distanceAcc do
		local root = humanoid.RootPart
		if not root or humanoid.Health <= 0 then continue end
		local material = humanoid.FloorMaterial
		if material == Enum.Material.Air then continue end
		local v = root.AssemblyLinearVelocity
		local horizontal = Vector3.new(v.X, 0, v.Z).Magnitude
		acc += horizontal * dt
		if acc >= STRIDE then
			acc -= STRIDE
			stepSound(humanoid, material)
		end
		distanceAcc[humanoid] = acc
	end
end)
```
Register/unregister humanoids via character added/removed (see [lifecycle](02-lifecycle-events.md)); one loop for
all characters, not one per character.

## Ledge detection sketch
```luau
--!strict
local function findLedge(root: BasePart, exclude: { Instance }, maxHeight: number): Vector3?
	local params = RaycastParams.new()
	params.ExcludeInstances = exclude
	local forward = root.CFrame.LookVector
	local base = root.Position - Vector3.new(0, 2.5, 0)            -- approx feet level for R15 (tune per rig)
	local knee = workspace:Raycast(base + Vector3.new(0, 1, 0), forward * 3, params)
	if not knee then return nil end
	local headClear = workspace:Raycast(base + Vector3.new(0, maxHeight + 0.5, 0), forward * 3, params) == nil
	if not headClear then return nil end
	local top = workspace:Raycast(knee.Position + forward * 0.8 + Vector3.new(0, maxHeight + 1, 0),
		Vector3.new(0, -(maxHeight + 1.5), 0), params)
	return if top then top.Position else nil
end
print(findLedge)
```

## Custom controller notes (ControllerManager)
Assign `RootPart`, add `GroundController`/`AirController`, sensors (`ControllerPartSensor` via `GroundSensor`/
`ClimbSensor`), set `MovingDirection`/`FacingDirection` each frame from input, switch `ActiveController` based on
sensor results. Budget time for edge cases (slopes, steps, moving platforms) that Humanoid already handles.

Sources: cd:characters/index, cd:reference/engine/classes/Humanoid, cd:reference/engine/enums/HumanoidStateType,
cd:characters/character-controller-library/index, cd:characters/character-controller-library/quick-start,
cd:reference/engine/classes/ControllerManager, cd:reference/engine/classes/GroundController,
cd:scripting/security/network-ownership, cd:workspace/raycasting.
