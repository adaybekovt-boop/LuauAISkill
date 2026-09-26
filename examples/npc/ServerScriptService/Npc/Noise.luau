--!strict
-- Gameplay noise events for AI hearing (not audio). Pure; portable vectors (.X/.Y/.Z only) → CLI-tested.
-- A noise of loudness L is audible to a listener with hearing range H if distance ≤ L × H.
-- Status: TYPECHECKED + CLI-EXECUTED.
export type Event = { pos: Vector3, loudness: number, time: number }
export type Noise = { events: { Event }, maxAge: number }

local Noise = {}

function Noise.new(maxAge: number): Noise
	return { events = {}, maxAge = maxAge }
end

function Noise.emit(n: Noise, pos: Vector3, loudness: number, now: number)
	table.insert(n.events, { pos = pos, loudness = loudness, time = now })
end

function Noise.prune(n: Noise, now: number)
	local keep = {}
	for _, e in n.events do
		if now - e.time <= n.maxAge then
			table.insert(keep, e)
		end
	end
	n.events = keep
end

-- Position of the most audible recent event for this listener, or nil.
function Noise.loudest(n: Noise, listener: Vector3, hearingRange: number, now: number): Vector3?
	local best: Event? = nil
	local bestScore = 0
	for _, e in n.events do
		if now - e.time > n.maxAge then
			continue
		end
		local dx, dy, dz = e.pos.X - listener.X, e.pos.Y - listener.Y, e.pos.Z - listener.Z
		local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
		if dist <= e.loudness * hearingRange then
			local score = e.loudness / math.max(dist, 1)
			if score > bestScore then
				best, bestScore = e, score
			end
		end
	end
	return if best then best.pos else nil
end

return Noise
