--!strict
-- Spring: damped harmonic spring for numbers (camera recoil, FOV kicks, UI motion). Frame-rate independent
-- for reasonable dt (dt is clamped). frequency in Hz, damping 1 = critical, < 1 = bouncy.
-- Status: TYPECHECKED + CLI-EXECUTED.

export type Spring = {
	position: number,
	velocity: number,
	target: number,
	frequency: number,
	damping: number,
}

local Spring = {}

function Spring.new(frequency: number, damping: number, initial: number?): Spring
	local p = initial or 0
	return { position = p, velocity = 0, target = p, frequency = frequency, damping = damping }
end

function Spring.step(s: Spring, dt: number): number
	dt = math.clamp(dt, 0, 1 / 30)
	local w = s.frequency * 2 * math.pi
	-- Two half steps improve stability for stiff springs at low frame rates.
	for _ = 1, 2 do
		local h = dt / 2
		local accel = w * w * (s.target - s.position) - 2 * s.damping * w * s.velocity
		s.velocity += accel * h
		s.position += s.velocity * h
	end
	return s.position
end

function Spring.impulse(s: Spring, velocity: number)
	s.velocity += velocity
end

-- Exponential smoothing factor for "move a fraction toward target this frame" (framerate independent).
function Spring.alpha(sharpness: number, dt: number): number
	return 1 - math.exp(-sharpness * dt)
end

return table.freeze(Spring)
