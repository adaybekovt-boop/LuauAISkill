--!strict
-- Mover: non-blocking path following for one Humanoid NPC. The manager calls update() on each think; nothing here
-- waits on MoveToFinished, so one manager thread can drive hundreds of NPCs.
--   * ComputeAsync runs in its own thread; a generation token discards results of superseded plans
--   * replans are throttled per NPC and capped globally (concurrent ComputeAsync calls)
--   * Path.Blocked ahead of us → replan; no progress for STUCK_TIME → jump, then replan; repeated → give up
--   * direct mode: plain MoveTo toward a visible target on similar height (cheaper and more precise)
-- Status: TYPECHECKED. Not run in Studio.
local PathfindingService = game:GetService("PathfindingService")

local ARRIVE_DISTANCE = 3
local REPLAN_INTERVAL = 0.75
local GOAL_MOVED = 4 -- replan only if the goal moved more than this
local STUCK_TIME = 1.5
local MAX_STUCK = 3
local MAX_CONCURRENT_PLANS = 4
local MOVETO_REFRESH = 3 -- Humanoid:MoveTo gives up after ~8 s; refresh well before

export type Mover = {
	humanoid: Humanoid,
	root: BasePart,
	agent: { [string]: any },
	goal: Vector3?,
	waypoints: { PathWaypoint },
	index: number,
	generation: number,
	lastPlan: number,
	blocked: RBXScriptConnection?,
	progressDist: number,
	progressTime: number,
	stuckCount: number,
	lastMoveTo: number,
	failed: boolean, -- no path / gave up; the brain treats this like "arrived" and moves on
}

local inFlight = 0
local Mover = {}

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

function Mover.new(humanoid: Humanoid, root: BasePart, agent: { [string]: any }): Mover
	return {
		humanoid = humanoid,
		root = root,
		agent = agent,
		goal = nil,
		waypoints = {},
		index = 1,
		generation = 0,
		lastPlan = -math.huge,
		blocked = nil,
		progressDist = math.huge,
		progressTime = 0,
		stuckCount = 0,
		lastMoveTo = -math.huge,
		failed = false,
	}
end

local function moveTo(m: Mover, pos: Vector3, now: number)
	m.humanoid:MoveTo(pos)
	m.lastMoveTo = now
end

local function plan(m: Mover, now: number)
	local goal = m.goal
	if not goal or inFlight >= MAX_CONCURRENT_PLANS or now - m.lastPlan < REPLAN_INTERVAL then
		return -- try again on a later think
	end
	m.lastPlan = now
	m.generation += 1
	local gen = m.generation
	inFlight += 1
	task.spawn(function()
		local path = PathfindingService:CreatePath(m.agent)
		local ok = pcall(path.ComputeAsync, path, m.root.Position, goal)
		inFlight -= 1
		if gen ~= m.generation then
			return -- superseded while computing
		end
		if m.blocked then
			m.blocked:Disconnect()
			m.blocked = nil
		end
		if not ok or path.Status ~= Enum.PathStatus.Success then
			m.waypoints, m.failed = {}, true
			return
		end
		m.waypoints, m.index, m.failed = path:GetWaypoints(), 2, false -- waypoint 1 is the start position
		m.progressDist, m.progressTime = math.huge, os.clock()
		m.blocked = path.Blocked:Connect(function(blockedIndex: number)
			if gen == m.generation and blockedIndex >= m.index then
				m.lastPlan = -math.huge -- allow an immediate replan
				plan(m, os.clock())
			end
		end)
		local wp = m.waypoints[m.index]
		if wp then
			moveTo(m, wp.Position, os.clock())
		end
	end)
end

-- Set a destination. `direct` = walk straight at it (caller verified line of sight and similar height).
function Mover.setGoal(m: Mover, goal: Vector3, direct: boolean, now: number)
	local moved = m.goal == nil or (goal - (m.goal :: Vector3)).Magnitude > GOAL_MOVED
	m.goal = goal
	if direct then
		m.generation += 1 -- cancel any path in progress
		m.waypoints = {}
		m.failed = false
		if moved or now - m.lastMoveTo > 0.25 then
			moveTo(m, goal, now)
		end
		return
	end
	if moved or (#m.waypoints == 0 and not m.failed) then
		m.stuckCount = 0
		plan(m, now)
	end
end

function Mover.stop(m: Mover)
	m.generation += 1
	m.goal, m.waypoints, m.failed = nil, {}, false
	m.humanoid:MoveTo(m.root.Position)
end

-- Advance along the path. Returns true when the goal is reached (or unreachable: check m.failed).
function Mover.update(m: Mover, now: number): boolean
	local goal = m.goal
	if not goal then
		return true
	end
	if flat(m.root.Position, goal) <= ARRIVE_DISTANCE and math.abs(m.root.Position.Y - goal.Y) < 6 then
		return true
	end
	if m.failed then
		return true
	end
	local wp = m.waypoints[m.index]
	local target = if wp then wp.Position else goal
	local dist = flat(m.root.Position, target)
	if wp and dist <= ARRIVE_DISTANCE then
		m.index += 1
		wp = m.waypoints[m.index]
		if wp then
			if wp.Action == Enum.PathWaypointAction.Jump then
				m.humanoid.Jump = true
			end
			moveTo(m, wp.Position, now)
			m.progressDist, m.progressTime = math.huge, now
		end
		return false
	end
	if now - m.lastMoveTo > MOVETO_REFRESH then
		moveTo(m, target, now)
	end
	-- Stuck detection: must get at least 0.5 studs closer every STUCK_TIME.
	if dist < m.progressDist - 0.5 then
		m.progressDist, m.progressTime = dist, now
	elseif now - m.progressTime > STUCK_TIME then
		m.stuckCount += 1
		m.progressDist, m.progressTime = dist, now
		if m.stuckCount > MAX_STUCK then
			m.failed = true
			return true
		end
		m.humanoid.Jump = true
		m.lastPlan = -math.huge
		plan(m, now)
	end
	return false
end

function Mover.destroy(m: Mover)
	m.generation += 1
	if m.blocked then
		m.blocked:Disconnect()
		m.blocked = nil
	end
end

return Mover
