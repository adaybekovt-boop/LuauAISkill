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
