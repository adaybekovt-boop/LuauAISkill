--!strict
-- Round HUD: reads Phase/EndsAt attributes and counts down locally (no per-second network traffic).
-- Status: TYPECHECKED. Not run in Studio.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local info = ReplicatedStorage:WaitForChild("Round", 30)
assert(info, "ReplicatedStorage.Round missing (is RoundServer running?)")

local gui = Instance.new("ScreenGui")
gui.Name = "RoundHud"
gui.ResetOnSpawn = false
local label = Instance.new("TextLabel")
label.AnchorPoint = Vector2.new(0.5, 0)
label.Position = UDim2.fromScale(0.5, 0.02)
label.Size = UDim2.fromScale(0.3, 0.05)
label.BackgroundTransparency = 1
label.TextScaled = true
label.TextColor3 = Color3.fromRGB(240, 240, 240)
label.TextStrokeTransparency = 0.5
label.Parent = gui
gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")

local TEXT = { Waiting = "Waiting for players", Intermission = "Next round in", InRound = "Time left", Results = "Round over" }

while true do
	local phase = info:GetAttribute("Phase")
	local endsAt = info:GetAttribute("EndsAt")
	local left = if type(endsAt) == "number" then math.max(0, math.ceil(endsAt - Workspace:GetServerTimeNow())) else 0
	local title = if type(phase) == "string" then TEXT[phase] or phase else ""
	if phase == "Results" then
		local winner = info:GetAttribute("Winner")
		label.Text = if type(winner) == "string" then `{winner} wins!` else title
	elseif phase == "Waiting" then
		label.Text = title
	else
		label.Text = `{title} {left // 60}:{string.format("%02d", left % 60)}`
	end
	task.wait(0.2)
end
