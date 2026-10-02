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
