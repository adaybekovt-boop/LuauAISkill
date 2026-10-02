local Lighting = game:GetService("Lighting")
local function enter()
    for i = 1, 30 do
        task.delay(i / 10, function()
            Lighting.Brightness = i % 2 == 0 and 5 or 0
        end)
    end
end
local function leave() Lighting.Brightness = 2 end
return { enter = enter, leave = leave }
