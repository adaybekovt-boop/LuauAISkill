-- BAD: intentional evaluation fixture.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local command = Instance.new("TextChatCommand")
command.PrimaryAlias = "/announce"
command.Parent = game:GetService("TextChatService")
local event = ReplicatedStorage:WaitForChild("Announcement")
command.Triggered:Connect(function(_source, unfilteredText)
    event:FireAllClients(unfilteredText)
end)
