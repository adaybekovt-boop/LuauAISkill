--!strict
-- Original reference example. NOT executed in Roblox Studio during pack creation.
-- Host: Roblox client ModuleScript
-- Owns only its own postprocess objects; never destroys unrelated Lighting effects.
local Lighting = game:GetService("Lighting")
export type Layer = {setReducedEffects: (reduced: boolean) -> (), destroy: () -> ()}
local VisualLayer = {}
function VisualLayer.new(): Layer
    local alive = true
    local bloom = Instance.new("BloomEffect")
    bloom.Name = "TKExample_Bloom"
    bloom.Intensity = 0.08 -- illustrative art choice, not a universal realistic preset
    bloom.Size = 16
    bloom.Threshold = 1.2
    bloom.Parent = Lighting
    local grade = Instance.new("ColorCorrectionEffect")
    grade.Name = "TKExample_Grade"
    grade.Brightness = 0
    grade.Contrast = 0.03
    grade.Saturation = -0.03
    grade.Parent = Lighting
    return {
        setReducedEffects = function(reduced: boolean): ()
            if not alive then return end
            bloom.Enabled = not reduced
            grade.Enabled = not reduced
        end,
        destroy = function(): ()
            if not alive then return end
            alive = false
            bloom:Destroy()
            grade:Destroy()
        end,
    }
end
return table.freeze(VisualLayer)
