# Physics: assemblies, ownership, constraints, spatial queries, collisions

## TL;DR
- Reason about assemblies rather than isolated parts.
- Assign ownership deliberately and validate client-influenced physics.
- Prefer current constraints over deprecated movers.
- Choose spatial queries for the shape of the test.
- Test stability under latency and changing ownership.

Read when: moving things physically, vehicles, projectiles, ragdolls, doors/platforms, hit detection queries.
Related: [security](04-security.md#movement-and-physics-ownership), [combat](15-combat.md),
[character controllers](13-character-controllers.md), [performance](08-performance.md#cpu-physics).

## Units and constants
1 stud = 0.28 m; 1 RMU (mass unit) = 21.952 kg; default `Workspace.Gravity` = 196.2 studs/s² (≈ 9.81 m/s² × 20).
Material density comes from `Enum.Material` unless `BasePart.CustomPhysicalProperties =
PhysicalProperties.new(density, friction, elasticity, frictionWeight, elasticityWeight)`.

## Assemblies
- An **assembly** = parts rigidly connected (welds, `WeldConstraint`, `Motor6D`, anchored-to-anchored...). Physics
  moves assemblies, not parts. Root part: `BasePart.AssemblyRootPart`; properties: `AssemblyLinearVelocity`,
  `AssemblyAngularVelocity`, `AssemblyMass`, `AssemblyCenterOfMass`.
- `BasePart.Velocity`/`RotVelocity` are deprecated → `AssemblyLinearVelocity`/`AssemblyAngularVelocity`.
- Impulses: `part:ApplyImpulse(v)`, `ApplyImpulseAtPosition`, `ApplyAngularImpulse` (on the owner's machine!).
- Anchored parts don't simulate; setting `CFrame` teleports (no collision resolution unless unanchored).
- Move whole models with `model:PivotTo(cf)`; many parts at once: `workspace:BulkMoveTo(parts, cframes,
  Enum.BulkMoveMode.FireCFrameChanged)` (much faster than a loop of CFrame writes).

## Network ownership
| Situation | Owner |
|---|---|
| Anchored | none (server authoritative) |
| Player's character | that client |
| Unanchored parts near a player | auto-assigned to nearby client (performance) |
| `part:SetNetworkOwner(nil)` | server (latency for clients, secure) |
| `part:SetNetworkOwner(player)` | that client (responsive, exploitable) |
| `part:SetNetworkOwnershipAuto()` | back to automatic |
Rules: call on the server; only works if `part:CanSetNetworkOwnership()` (not anchored, not welded to anchored).
The owner simulates and replicates positions; everyone else interpolates. Forces/impulses/velocity writes must
happen **on the owner** to take effect. A client that owns an assembly can set any position/velocity — validate
outcomes on the server. `Touched` events come from the simulating machine.

## Movers and constraints (modern — BodyMovers are deprecated)
| Goal | Use | Key properties |
|---|---|---|
| Hold/drive velocity | `LinearVelocity` | `VelocityConstraintMode` (Vector/Line/Plane), `VectorVelocity`, `MaxForce`, `RelativeTo`, `Attachment0` |
| Spin | `AngularVelocity` | `AngularVelocity`, `MaxTorque` |
| Move to a point (springy) | `AlignPosition` | `Mode` (OneAttachment/TwoAttachment), `Position`, `Responsiveness`, `MaxForce`, `RigidityEnabled` |
| Rotate to an orientation | `AlignOrientation` | `Mode`, `CFrame`, `Responsiveness`, `MaxTorque`, `RigidityEnabled`, `PrimaryAxisOnly` |
| Constant force (thrust, anti-gravity) | `VectorForce` | `Force`, `RelativeTo`, `ApplyAtCenterOfMass` |
| Constant torque | `Torque` | `Torque` |
| Pull along a line | `LineForce` | `Magnitude`, `InverseSquareLaw` |
| Door hinge / wheel axle | `HingeConstraint` | `ActuatorType` Motor/Servo, `TargetAngle`, `AngularSpeed`, `LimitsEnabled` |
| Suspension | `SpringConstraint` / `CylindricalConstraint` | `Stiffness`, `Damping`, `FreeLength` |
| Rope / rod | `RopeConstraint` / `RodConstraint` | `Length` |
| Ragdoll joints | `BallSocketConstraint` (+ `LimitsEnabled`, `TwistLimitsEnabled`) | `UpperAngle`, `TwistLowerAngle/UpperAngle` |
| Weld at runtime | `WeldConstraint` (keeps current offset) or `Weld` (C0/C1) | `Part0`, `Part1` |
| Ignore collisions between two parts | `NoCollisionConstraint` | `Part0`, `Part1` |
| Animated joint that physics respects | `AnimationConstraint` | used by animation system/IK |
BodyVelocity → LinearVelocity; BodyGyro → AlignOrientation; BodyPosition → AlignPosition; BodyForce →
VectorForce; BodyAngularVelocity → AngularVelocity; BodyThrust → VectorForce with offset/Torque; RocketPropulsion
→ AlignPosition + AlignOrientation.

```luau
--!strict
-- Hover platform: AlignPosition toward a target, AlignOrientation keeps it level.
local function makeHover(part: BasePart, target: Vector3)
	local attachment = Instance.new("Attachment")
	attachment.Parent = part
	local align = Instance.new("AlignPosition")
	align.Mode = Enum.PositionAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.Position = target
	align.Responsiveness = 20
	align.MaxForce = part.AssemblyMass * workspace.Gravity * 4
	align.Parent = part
	local orient = Instance.new("AlignOrientation")
	orient.Mode = Enum.OrientationAlignmentMode.OneAttachment
	orient.Attachment0 = attachment
	orient.CFrame = CFrame.new()
	orient.Responsiveness = 15
	orient.Parent = part
end
local p = Instance.new("Part")
p.Parent = workspace
makeHover(p, Vector3.new(0, 20, 0))
```

## Moving platforms, elevators, doors
- Kinematic platform with riders: unanchored part driven by `AlignPosition`/`PrismaticConstraint` with
  `SetNetworkOwner(nil)` so characters stand on it correctly; or anchored + TweenService **on clients** for
  cosmetic doors (server holds state as an attribute).
- Anchored CFrame-tweened platforms don't carry characters reliably (no velocity) — prefer constraints.

## Spatial queries
| Query | API | Notes |
|---|---|---|
| Ray | `workspace:Raycast(origin, direction, params)` | direction length = distance (max 15,000 studs); returns `RaycastResult?` (`Instance`, `Position`, `Normal`, `Distance`, `Material`) |
| Swept sphere / box / part | `Spherecast(pos, radius, dir, params)`, `Blockcast(cf, size, dir, params)`, `Shapecast(part, dir, params)` | **don't detect parts initially overlapping** the shape; good for melee sweeps, thick bullets, character-sized probes |
| Overlap | `GetPartBoundsInBox(cf, size, overlapParams)`, `GetPartBoundsInRadius(pos, r, op)`, `GetPartsInPart(part, op)` | bounds versions test AABBs (cheap, coarse); `GetPartsInPart` uses true geometry |
Params:
```luau
--!strict
local effects = workspace:FindFirstChild("Effects")
local hitboxes = workspace:FindFirstChild("Hitboxes")
local params = RaycastParams.new()
params.ExcludeInstances = if effects then { effects } else {}  -- new API (2026): ExcludeInstances / IncludeInstances
params.IgnoreWater = true
params.CollisionGroup = "Projectiles"   -- respect collision group rules
local overlap = OverlapParams.new()
overlap.IncludeInstances = if hitboxes then { hitboxes } else {}
overlap.MaxParts = 16
local hit = workspace:Raycast(Vector3.new(0, 50, 0), Vector3.new(0, -100, 0), params)
if hit then print(hit.Instance:GetFullName(), hit.Normal) end
```
- `RaycastParams.ExcludeInstances`/`IncludeInstances` supersede `FilterDescendantsInstances` + `FilterType` (still
  works; `Enum.RaycastFilterType` now has only `Exclude`/`Include` — old `Blacklist`/`Whitelist` are gone).
  Both lists can be combined; exclusion wins.
- Reuse params objects (they're mutable); rebuild filter arrays only when membership changes.
- `BasePart.CanQuery = false` removes a part from all queries (still collides if `CanCollide`).
- Streaming: clients can't hit what isn't streamed in; streaming imposters aren't query targets.

## Collisions
- Flags per part: `CanCollide` (physical contact), `CanTouch` (Touched events), `CanQuery` (raycasts/overlaps).
- Collision groups (max 32): `PhysicsService:RegisterCollisionGroup("Ghost")`,
  `PhysicsService:CollisionGroupSetCollidable("Ghost", "Default", false)`, then `part.CollisionGroup = "Ghost"`.
  (`CreateCollisionGroup`, `SetPartCollisionGroup`, `CollisionGroupId` are deprecated.) Register on the server at
  startup; groups replicate.
- Mesh collision: `CollisionFidelity` Box/Hull/Default/PreciseConvexDecomposition is a Studio-time setting (not
  writable by scripts). Use invisible simple parts for complex colliders.
- Fast projectiles tunnel through thin walls → raycast/spherecast per step between previous and current position
  instead of relying on physics collisions.

## Stability tips
- Mass ratios > ~100:1 in one mechanism get jittery; use `Massless` for decorative welded parts (only affects
  non-root parts of an assembly).
- Don't fight physics: writing `CFrame` of an unanchored simulated part every frame from a script teleports it and
  wakes the solver; use constraints.
- Ragdoll: disable `Motor6D`s (or `Humanoid.BreakJointsOnDeath` flow), add BallSocketConstraints between limb
  attachments, set `Humanoid:ChangeState(Enum.HumanoidStateType.Physics)` on the owning machine, add
  NoCollisionConstraints between adjacent limbs. See [combat](15-combat.md#ragdoll-on-death-or-knock-down).
- Vehicles: `VehicleSeat` + HingeConstraint motors/`CylindricalConstraint` suspension; give the driver network
  ownership for responsiveness and validate speed on the server.
- Fluid forces (`BasePart.EnableFluidForces`, aerodynamics) exist for planes/gliders — verify behaviour in docs.

Sources: cd:physics/index, cd:physics/units, cd:physics/assemblies, cd:physics/network-ownership,
cd:physics/mover-constraints, cd:physics/mechanical-constraints, cd:physics/constraints/align-position,
cd:physics/constraints/linear-velocity, cd:physics/sleep-system, cd:physics/adaptive-timestepping,
cd:workspace/raycasting, cd:workspace/collisions, cd:reference/engine/classes/WorldRoot,
cd:reference/engine/datatypes/RaycastParams, cd:reference/engine/datatypes/OverlapParams,
cd:reference/engine/classes/PhysicsService.
