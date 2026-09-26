--!strict
-- Pure decision logic for a horror-style monster: Patrol → Investigate → Chase → Search → Patrol.
-- No Roblox APIs (positions are stored, never computed) → CLI-tested in examples/tests/npc.spec.luau.
-- Status: TYPECHECKED + CLI-EXECUTED.
export type State = "Patrol" | "Investigate" | "Chase" | "Search"
export type Params = {
	detectGrace: number, -- seconds of continuous sight before a chase starts (fairness)
	loseSightTime: number, -- keep chasing to the last seen position this long after losing sight
	investigateTime: number,
	searchTime: number,
}
export type Memory = {
	state: State,
	since: number, -- when the current state started
	seenSince: number?, -- start of the current continuous sighting
	lastSeenPos: Vector3?,
	lastSeenTime: number,
	goal: Vector3?, -- where to go in Investigate/Search/Chase
}
export type Senses = {
	now: number,
	seePos: Vector3?, -- target position if visible this think
	hearPos: Vector3?, -- loudest audible noise, if any
	atGoal: boolean, -- mover reports arrival
}

local Brain = {}

function Brain.new(now: number): Memory
	return { state = "Patrol", since = now, seenSince = nil, lastSeenPos = nil, lastSeenTime = -math.huge, goal = nil }
end

local function enter(m: Memory, state: State, now: number, goal: Vector3?)
	if m.state ~= state then
		m.state = state
		m.since = now
	end
	m.goal = goal
end

-- A new noise interrupts anything except an ongoing investigation (which already has a goal).
local function heardNew(m: Memory): boolean
	return m.state ~= "Investigate"
end

-- Returns the state to act on and whether to run (true) or walk.
function Brain.think(m: Memory, s: Senses, p: Params): (State, boolean)
	local now = s.now
	if s.seePos then
		m.seenSince = m.seenSince or now
		m.lastSeenPos = s.seePos
		m.lastSeenTime = now
		if m.state == "Chase" or now - (m.seenSince :: number) >= p.detectGrace then
			enter(m, "Chase", now, s.seePos)
		else
			enter(m, "Investigate", now, s.seePos) -- noticed something: turn toward it, walk, give the player a moment
		end
	else
		m.seenSince = nil
		if m.state == "Chase" then
			if now - m.lastSeenTime > p.loseSightTime then
				enter(m, "Search", now, m.lastSeenPos)
			end
		elseif s.hearPos ~= nil and heardNew(m) then
			enter(m, "Investigate", now, s.hearPos)
		elseif m.state == "Investigate" and (s.atGoal or now - m.since > p.investigateTime) then
			enter(m, "Search", now, m.goal)
		elseif m.state == "Search" and now - m.since > p.searchTime then
			enter(m, "Patrol", now, nil)
		end
	end
	return m.state, m.state == "Chase"
end

return table.freeze(Brain)
