--!strict
export type DashData = { cooldown: number, remaining: number, held: boolean }
local Model = {}
function Model.step(previous: DashData, pressed: boolean, dt: number): (DashData, boolean)
	local delta = math.clamp(dt, 0, 1 / 30)
	local cooldown = math.max(0, previous.cooldown - delta)
	local remaining = math.max(0, previous.remaining - delta)
	local start = pressed and not previous.held and cooldown == 0
	if start then cooldown, remaining = 1.5, 0.18 end
	return { cooldown = cooldown, remaining = remaining, held = pressed }, start
end
return Model
