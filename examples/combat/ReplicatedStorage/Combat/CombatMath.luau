--!strict
-- Pure combat math shared by server validation and client prediction.
-- "Portable vectors": only operators and .X/.Y/.Z are used, so the same code runs on Roblox Vector3 values and on
-- the Luau CLI's native vectors (examples/tests/combat.spec.luau). Never constructs Vector3s itself.
-- Status: TYPECHECKED + CLI-EXECUTED.
local CombatMath = {}

function CombatMath.length(v: Vector3): number
	return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
end

function CombatMath.dot(a: Vector3, b: Vector3): number
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end

function CombatMath.finite(v: Vector3): boolean
	local s = v.X + v.Y + v.Z
	return s == s and s ~= math.huge and s ~= -math.huge
end

-- Target inside a horizontal cone in front of `origin` (melee). Height is checked separately by the caller's box.
function CombatMath.inCone(origin: Vector3, forward: Vector3, target: Vector3, reach: number, halfAngleDeg: number): boolean
	local dx, dz = target.X - origin.X, target.Z - origin.Z
	local dist = math.sqrt(dx * dx + dz * dz)
	if dist > reach then
		return false
	end
	if dist < 1e-3 then
		return true
	end
	local fl = math.sqrt(forward.X * forward.X + forward.Z * forward.Z)
	if fl < 1e-6 then
		return false
	end
	local cos = (forward.X * dx + forward.Z * dz) / (fl * dist)
	return cos >= math.cos(math.rad(halfAngleDeg))
end

-- Minimum seconds between shots for `rpm`, with a tolerance fraction for network jitter (0.1 = 10 % faster allowed).
function CombatMath.canFire(lastShot: number, now: number, rpm: number, tolerance: number): boolean
	return now - lastShot >= (60 / rpm) * (1 - tolerance)
end

-- Damage with linear falloff between falloffStart and range.
function CombatMath.falloff(damage: number, distance: number, falloffStart: number, range: number, minMult: number): number
	if distance <= falloffStart then
		return damage
	end
	local t = math.clamp((distance - falloffStart) / math.max(range - falloffStart, 1e-6), 0, 1)
	return damage * (1 + (minMult - 1) * t)
end

-- Kinematic projectile: position after t seconds (gravity is a downward acceleration vector).
function CombatMath.ballistic(origin: Vector3, velocity: Vector3, gravity: Vector3, t: number): Vector3
	return origin + velocity * t + gravity * (0.5 * t * t)
end

return table.freeze(CombatMath)
