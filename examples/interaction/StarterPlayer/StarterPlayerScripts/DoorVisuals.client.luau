--!strict
-- Client door animation. Reads the server-owned "Swing" attribute and rotates the door's Visual model around the
-- Hinge locally (official guidance: tween on clients, not the server — server tweens replicate every frame and
-- jitter). Streaming-safe: a door that streams in applies its current state instantly.
-- Status: TYPECHECKED. Not run in Studio.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Binder = require(ReplicatedStorage.Lib.Binder)

local OPEN_TIME = 0.55
local DEFAULT_ANGLE = 95 -- degrees; per-door override: attribute OpenAngle
local RATTLE_TIME = 0.25

type Anim = {
	visual: Model,
	hinge: CFrame,
	offset: CFrame, -- visual pivot relative to the hinge when closed
	angle: number, -- current radians
	from: number,
	to: number,
	t: number,
	duration: number,
	rattle: number, -- seconds of rattle left
}

local animating: { [Anim]: true } = {}
local stepConnection: RBXScriptConnection? = nil

local function apply(a: Anim, extra: number)
	a.visual:PivotTo(a.hinge * CFrame.Angles(0, a.angle + extra, 0) * a.offset)
end

local function step(dt: number)
	for a in animating do
		a.t = math.min(a.t + dt, a.duration)
		local alpha = TweenService:GetValue(a.t / a.duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		a.angle = a.from + (a.to - a.from) * alpha
		local extra = 0
		if a.rattle > 0 then
			a.rattle = math.max(0, a.rattle - dt)
			extra = math.rad(1.5) * math.sin(a.rattle * 60) * (a.rattle / RATTLE_TIME)
		end
		apply(a, extra)
		if a.t >= a.duration and a.rattle <= 0 then
			animating[a] = nil
		end
	end
	if next(animating) == nil and stepConnection then
		stepConnection:Disconnect() -- no per-frame cost while every door is idle
		stepConnection = nil
	end
end

local function start(a: Anim)
	animating[a] = true
	if not stepConnection then
		stepConnection = RunService.PreRender:Connect(step)
	end
end

local function targetAngle(door: Instance): number
	local swing = door:GetAttribute("Swing")
	local degrees = door:GetAttribute("OpenAngle")
	local open = if type(degrees) == "number" and degrees == degrees then math.clamp(degrees, 0, 180) else DEFAULT_ANGLE
	return if type(swing) == "number" then math.rad(open) * math.clamp(swing, -1, 1) else 0
end

Binder.bind("Door", function(door, cleanup)
	local visual = door:FindFirstChild("Visual")
	local hingePart = door:FindFirstChild("Hinge")
	if not (visual and visual:IsA("Model") and hingePart and hingePart:IsA("BasePart")) then
		warn("Door is missing Visual (Model) or Hinge (Part):", door:GetFullName())
		return
	end
	local a: Anim = {
		visual = visual,
		hinge = hingePart.CFrame,
		offset = hingePart.CFrame:ToObjectSpace(visual:GetPivot()),
		angle = 0,
		from = 0,
		to = 0,
		t = 0,
		duration = OPEN_TIME,
		rattle = 0,
	}
	-- NOTE: `offset` assumes the door is authored closed in Studio (the server never moves the Visual).
	a.angle = targetAngle(door)
	a.to = a.angle
	apply(a, 0) -- streamed-in or late-joining clients snap to the current state

	cleanup:connect(door:GetAttributeChangedSignal("Swing"), function()
		a.from, a.to, a.t = a.angle, targetAngle(door), 0
		start(a)
	end)
	cleanup:connect(door:GetAttributeChangedSignal("DeniedAt"), function()
		a.rattle = RATTLE_TIME
		a.from, a.to, a.t = a.angle, a.angle, a.duration
		start(a)
	end)
	cleanup:add(function()
		animating[a] = nil
	end)
end)
