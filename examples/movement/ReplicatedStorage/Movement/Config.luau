--!strict
-- Movement tuning shared by client (feel) and server (validation). Units: studs, seconds.
local Config = {
	WALK_SPEED = 16, -- Humanoid default
	SPRINT_SPEED = 24,
	CROUCH_SPEED = 8,
	CROUCH_CAMERA_DROP = 1.6, -- Humanoid.CameraOffset.Y while crouched
	SPRINT_MIN_FORWARD = 0.5, -- MoveDirection · look must exceed this to sprint (no sideways/backwards sprint)
	STAMINA = {
		max = 100,
		drainPerSecond = 18,
		regenPerSecond = 22,
		regenDelay = 1.2, -- seconds after sprinting stops before regen starts
		startThreshold = 15, -- can't start sprinting below this (prevents stutter-sprinting at 0)
	},
	-- Server speed validation: allowed horizontal speed = expected * (1 + SPEED_TOLERANCE) + SPEED_SLACK.
	SPEED_TOLERANCE = 0.25,
	SPEED_SLACK = 4,
}
return table.freeze(Config)
