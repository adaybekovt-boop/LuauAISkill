--!strict
-- Original reference example. NOT executed in Roblox Studio during pack creation.
-- Host: Roblox client ModuleScript
-- Routes a caller-prepared AudioPlayer to output; caller owns asset permissions and the player.
export type Release = () -> ()
local SoundService = game:GetService("SoundService")
local AudioGraph = {}
function AudioGraph.connect2D(source: AudioPlayer): Release
    -- Configure source asset in Studio or a verified adapter. No guessed asset IDs.
    local output = Instance.new("AudioDeviceOutput")
    output.Name = "TKExample_Output"
    output.Parent = SoundService
    local wire = Instance.new("Wire")
    wire.Name = "TKExample_Wire"
    wire.SourceInstance = source
    wire.TargetInstance = output
    wire.Parent = output
    local alive = true
    return function(): ()
        if not alive then return end
        alive = false
        wire:Destroy()
        output:Destroy()
        -- Source may be used elsewhere: this helper does NOT stop/destroy it.
    end
end
return table.freeze(AudioGraph)
