# First-person cosmetic viewmodel with lifecycle cleanup

A local two-arm/gadget rig built from primitives, composed after the camera controller without taking ownership
of Camera.CFrame, with bounded sway, wall retreat, Reduced Motion, camera replacement, respawn and tool hiding.

Evidence: **TYPECHECKED** (strict, old + new solver, pinned Roblox definitions); pure logic **CLI-EXECUTED**.
**Studio / live: NOT RUN.**

## Architecture
- The existing camera remains the only Camera.CFrame writer. This script binds at Camera render priority + 1
  and rebuilds the local model pose from that frame's camera; it never compounds prior transforms.
- All parts are anchored, non-collidable, non-touchable, non-queryable and shadowless. The model is client-only
  under CurrentCamera. No server remote, hit detection, entitlement, or ammo state is involved.
- A bounded frame-rate-independent sway reducer handles mouse deltas and resets for Reduced Motion. Neutral
  rendering works on gamepad/touch; those devices do not receive invented mouse sway.
- A camera blockcast excludes character/model, retreats the gadget modestly, and hides it at close obstructions.
  It hides in third person, cutscenes that move the camera, death, while holding a real Tool, or on explicit disable.
- Character removal detaches the rig; replacement cameras are followed every frame. Script destruction unbinds,
  disconnects, destroys the model and restores its first-person setting if still owned.

## When NOT to use

not a weapon framework or an avatar cloning pipeline. Do not make damage raycasts originate
from these visual arms. If your project owns camera mode or render scheduling already, integrate the viewmodel as
one layer there and remove the demo's `CameraMode` assignment. Never clone arbitrary Tool scripts into the rig.

## Setup and integration
Copy `examples/viewmodel` by service folder. This self-contained demo requests LockFirstPerson, shows the local
rig for a living character, and uses no assets or animation IDs. Set local `ViewmodelDisabled` for menus/cutscenes
and `ReducedMotion` for the user's comfort preference. To add an authored rig later, preserve its local visual-only
properties and use authorized animations with an Animator; do not transplant gameplay Scripts. A real equipped
Tool hides the demonstration gadget rather than displaying a duplicate weapon.

## Implementation

### `examples/viewmodel/ReplicatedStorage/Viewmodel/Sway.luau`

<!-- code: examples/viewmodel/ReplicatedStorage/Viewmodel/Sway.luau -->
```luau
-- file: examples/viewmodel/ReplicatedStorage/Viewmodel/Sway.luau
--!strict
local Sway = {}
export type SwayData = { x: number, y: number }
function Sway.step(state: SwayData, dx: number, dy: number, dt: number, reduced: boolean): SwayData
    if reduced then return { x = 0, y = 0 } end
    local alpha = 1 - math.exp(-14 * math.clamp(dt, 0, 0.1))
    return { x = state.x + (math.clamp(dx, -20, 20) * 0.0015 - state.x) * alpha,
        y = state.y + (math.clamp(dy, -20, 20) * 0.0015 - state.y) * alpha }
end
return Sway
```
<!-- /code -->

### `examples/viewmodel/StarterPlayer/StarterPlayerScripts/ViewmodelClient.client.luau`

<!-- code: examples/viewmodel/StarterPlayer/StarterPlayerScripts/ViewmodelClient.client.luau -->
```luau
-- file: examples/viewmodel/StarterPlayer/StarterPlayerScripts/ViewmodelClient.client.luau
--!strict
-- Cosmetic demonstration. Camera controller keeps sole ownership of Camera.CFrame.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Sway = require(ReplicatedStorage.Viewmodel.Sway)
local player = Players.LocalPlayer :: Player
local oldMode = player.CameraMode
player.CameraMode = Enum.CameraMode.LockFirstPerson
local model = Instance.new("Model")
model.Name = "LocalViewmodel"
local function visual(name: string, size: Vector3, offset: CFrame, color: Color3): Part
    local p = Instance.new("Part")
    p.Name = name; p.Size = size; p.CFrame = offset; p.Color = color
    p.Anchored = true; p.CanCollide = false; p.CanTouch = false; p.CanQuery = false
    p.CastShadow = false; p.Parent = model
    return p
end
local root = visual("Root", Vector3.new(0.1, 0.1, 0.1), CFrame.identity, Color3.new())
root.Transparency = 1
visual("LeftArm", Vector3.new(0.4, 0.45, 1.5), CFrame.new(-0.65, -0.7, -1), Color3.fromRGB(170, 135, 110))
visual("RightArm", Vector3.new(0.4, 0.45, 1.5), CFrame.new(0.65, -0.7, -1), Color3.fromRGB(170, 135, 110))
visual("Gadget", Vector3.new(0.7, 0.55, 1.4), CFrame.new(0.4, -0.5, -1.7), Color3.fromRGB(70, 80, 85))
model.PrimaryPart = root
local state: Sway.SwayData = { x = 0, y = 0 }
local params = RaycastParams.new()
local BINDING = "RecipeViewmodelAfterCamera"
local activeCharacter: Model? = nil
local function updateCharacter(character: Model?)
    activeCharacter = character
    state = { x = 0, y = 0 }
    params.ExcludeInstances = if character then { model, character } else { model }
end
updateCharacter(player.Character)
local added = player.CharacterAdded:Connect(updateCharacter)
local removing = player.CharacterRemoving:Connect(function() updateCharacter(nil); model.Parent = nil end)
RunService:BindToRenderStep(BINDING, Enum.RenderPriority.Camera.Value + 1, function(dt: number)
    local camera = workspace.CurrentCamera
    local character = activeCharacter
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local head = character and character:FindFirstChild("Head")
    local firstPerson = camera and head and head:IsA("BasePart")
        and (camera.CFrame.Position - head.Position).Magnitude < 1
    -- Hide during death, cutscene, third person or a real Tool, preventing duplicate weapon renders.
    if not camera or not character or not humanoid or humanoid.Health <= 0 or not firstPerson
        or character:FindFirstChildOfClass("Tool") or player:GetAttribute("ViewmodelDisabled") == true then
        model.Parent = nil; return
    end
    model.Parent = camera -- follows replacement cameras and reappears after respawn
    local delta = UserInputService:GetMouseDelta()
    state = Sway.step(state, delta.X, delta.Y, dt, player:GetAttribute("ReducedMotion") == true)
    local hit = workspace:Blockcast(camera.CFrame, Vector3.new(0.7, 0.7, 0.1), camera.CFrame.LookVector * 2.2, params)
    if hit and hit.Distance < 1 then model.Parent = nil; return end
    local retreat = if hit then math.clamp(2.2 - hit.Distance, 0, 0.35) else 0
    -- Rebuild from the camera each frame; never compound offsets onto the previous model pose.
    model:PivotTo(camera.CFrame * CFrame.new(0, -retreat * 0.2, retreat)
        * CFrame.Angles(-state.y, -state.x, -state.x * 0.5))
end)
script.Destroying:Connect(function()
    RunService:UnbindFromRenderStep(BINDING)
    added:Disconnect(); removing:Disconnect(); model:Destroy()
    if player.CameraMode == Enum.CameraMode.LockFirstPerson then player.CameraMode = oldMode end
end)
```
<!-- /code -->

## How to test

| Scenario | Required observation |
|---|---|
| CLI reducer | Input/dt bounded; previous state unchanged; Reduced Motion yields zero offset |
| Play, rotate camera rapidly | No accumulated drift; default camera retains sole ownership |
| Camera replaced / first-to-third person | Model reparents or hides; no orphan camera children |
| Respawn / death / equip Tool | Model hides/reappears without duplicate rigs or stale character references |
| Approach wall / geometry streams in | No forward gadget clipping through a close obstruction; no unbounded waits |
| Reduced Motion / touch / gamepad | Sway disabled or neutral as appropriate; no forced shake |
| Destroy/restart controller | Binding and GUI-independent model removed; owned setting restored |

Use screenshots/video on target aspect ratios, FOVs and devices. Static geometry has no animation-quality guarantee.

## Failure paths and limits
Parts can still be visually clipped by the camera near plane or thin/transparent geometry; Studio art direction
must tune sizes and offsets. No world avatar transparency is rewritten, avoiding conflict with the default camera
transparency controller. For a full weapon rig, add equip/unequip state and animation lifetimes to this same owner.
This example intentionally omits invented asset IDs, recoil gameplay and claims about what other players see.

## Verification
From the skill directory, run `python tools/check_all.py`. Pure tests for this recipe:
`luau examples/tests/viewmodel.spec.luau`. The checker runs both Luau solvers. Engine coverage remains NOT RUN until you retain
assertion output from the specified Studio scenario with Studio build, place revision, peers, and device.

Sources: cd:reference/engine/classes/Camera, cd:reference/engine/classes/RunService, cd:reference/engine/classes/Workspace, api:RunService.BindToRenderStep, api:Workspace.Blockcast.
