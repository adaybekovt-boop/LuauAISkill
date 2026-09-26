--!strict
-- Original reference example. NOT executed in Roblox Studio during pack creation.
-- Host: Roblox shared ModuleScript
-- Tracks one Player's character replacement. Callback must be non-yielding.
export type Release = () -> ()
local CharacterBinding = {}
function CharacterBinding.bind(player: Player, attach: (Model) -> Release): Release
    local active = true
    local current: Model? = nil
    local release: Release? = nil
    local function detach(): ()
        current = nil
        local old = release
        release = nil
        if old then
            local ok, err = pcall(old)
            if not ok then warn("Character cleanup failed:", err) end
        end
    end
    local function added(character: Model): ()
        if not active or character == current then return end
        detach()
        current = character
        local ok, result = pcall(attach, character)
        if not ok then
            warn("Character attach failed:", result)
            if current == character then current = nil end
            return
        end
        local cleanup = result :: Release
        if active and current == character then release = cleanup
        else
            local cleanOk, cleanErr = pcall(cleanup)
            if not cleanOk then warn("Late character cleanup failed:", cleanErr) end
        end
    end
    local c1 = player.CharacterAdded:Connect(added)
    local c2 = player.CharacterRemoving:Connect(function(character: Model)
        if character == current then detach() end
    end)
    if player.Character then added(player.Character) end
    return function(): ()
        if not active then return end
        active = false
        c1:Disconnect()
        c2:Disconnect()
        detach()
    end
end
return table.freeze(CharacterBinding)
