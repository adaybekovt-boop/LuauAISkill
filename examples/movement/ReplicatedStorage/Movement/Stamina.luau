--!strict
-- Pure stamina model used identically by client (prediction/UI) and server (authority). CLI-tested.
-- Status: TYPECHECKED + CLI-EXECUTED (examples/tests/movement.spec.luau).
export type Params = {
	max: number,
	drainPerSecond: number,
	regenPerSecond: number,
	regenDelay: number,
	startThreshold: number,
}
export type Stamina = { value: number, sinceDrain: number, params: Params }

local Stamina = {}

function Stamina.new(params: Params): Stamina
	return { value = params.max, sinceDrain = math.huge, params = params }
end

-- Advance by dt. Returns true while `draining` is allowed to continue (false = ran out → force stop).
function Stamina.step(s: Stamina, dt: number, draining: boolean): boolean
	local p = s.params
	dt = math.clamp(dt, 0, 1) -- a long hitch must not grant or drain a huge amount at once
	if draining then
		s.value = math.max(0, s.value - p.drainPerSecond * dt)
		s.sinceDrain = 0
		return s.value > 0
	end
	s.sinceDrain += dt
	if s.sinceDrain >= p.regenDelay then
		s.value = math.min(p.max, s.value + p.regenPerSecond * dt)
	end
	return true
end

function Stamina.canStart(s: Stamina): boolean
	return s.value >= s.params.startThreshold
end

return table.freeze(Stamina)
