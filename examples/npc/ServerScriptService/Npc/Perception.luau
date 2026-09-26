--!strict
-- Vision for NPCs: cheap checks first (distance, view cone), raycast last. Server-side, server positions only.
-- Status: TYPECHECKED. Not run in Studio.
local Workspace = game:GetService("Workspace")

local Perception = {}

-- Returns the target's head position if `eye` can see it. `look` is the NPC's facing direction.
function Perception.canSee(eye: Vector3, look: Vector3, npc: Model, target: Model, range: number,
	halfFovDeg: number): Vector3?
	local head = target:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return nil
	end
	local offset = head.Position - eye
	local dist = offset.Magnitude
	if dist > range or dist < 1e-3 then
		return nil
	end
	if look:Dot(offset / dist) < math.cos(math.rad(halfFovDeg)) then
		return nil
	end
	local params = RaycastParams.new()
	params.ExcludeInstances = { npc }
	local hit = Workspace:Raycast(eye, offset, params)
	if hit and not hit.Instance:IsDescendantOf(target) then
		return nil -- something in the way
	end
	return head.Position
end

return Perception
