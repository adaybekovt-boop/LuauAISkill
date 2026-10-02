--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remote = ReplicatedStorage:WaitForChild("LeaderboardQuery", 20) :: RemoteEvent?
if not remote then return end
local player = Players.LocalPlayer :: Player
local gui = Instance.new("ScreenGui")
gui.Name = "Leaderboard"; gui.ResetOnSpawn = false
local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(280, 440); frame.Position = UDim2.fromOffset(16, 80); frame.Parent = gui
local label = Instance.new("TextLabel")
label.Size = UDim2.new(1, 0, 1, -40); label.Position = UDim2.fromOffset(0, 40)
label.TextSize = 16; label.TextYAlignment = Enum.TextYAlignment.Top
label.RichText = false; label.AutoLocalize = false; label.Text = "Loading scores…"; label.Parent = frame
local current = "global"
local running = true
for index, mode in { "global", "friends" } do
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(0.5, 0, 0, 36); button.Position = UDim2.new((index - 1) * 0.5, 0, 0, 0)
    button.Text = mode; button.Parent = frame
    button.Activated:Connect(function() current = mode; remote:FireServer(mode) end)
end
gui.Parent = player:WaitForChild("PlayerGui")
local response = remote.OnClientEvent:Connect(function(mode: string, snapshot: any)
    if mode ~= current then return end
    local lines = { if snapshot.stale then "Scores unavailable / cached" else "Best scores" }
    if snapshot.partial then table.insert(lines, "Limited to first 99 friend IDs + you") end
    for rank, row in snapshot.rows do table.insert(lines, `{rank}. User {row.userId}: {row.score}`) end
    if #snapshot.rows == 0 then table.insert(lines, "No recorded scores") end
    label.Text = table.concat(lines, "\n")
end)
remote:FireServer(current)
task.spawn(function()
    while running do
        task.wait(65)
        if running then remote:FireServer(current) end
    end
end)
script.Destroying:Connect(function() running = false; response:Disconnect(); gui:Destroy() end)
-- User IDs avoid per-row username API bursts. Add a bounded name cache if your UI needs names.
