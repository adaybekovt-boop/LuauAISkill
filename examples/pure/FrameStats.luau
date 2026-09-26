--!strict
-- Original reference example. NOT executed in Roblox Studio during pack creation.
-- Host: pure Luau
-- Bounded samples of observed frame interval; not CPU/GPU timing.
export type Snapshot = {count: number, meanMs: number, p95Ms: number, p99Ms: number, maxMs: number}
export type Collector = {push: (dt: number) -> (), snapshot: () -> Snapshot?}
local FrameStats = {}
function FrameStats.new(capacity: number): Collector
    assert(capacity >= 1 and capacity < math.huge and capacity % 1 == 0, "Invalid capacity")
    local values: {number} = {}
    local nextIndex = 1
    return {
        push = function(dt: number): ()
            if dt ~= dt or dt <= 0 or dt >= math.huge then
                return
            end
            local ms = dt * 1000
            if ms >= math.huge then return end
            values[nextIndex] = ms
            nextIndex = (nextIndex % capacity) + 1
        end,
        snapshot = function(): Snapshot?
            local count = #values
            if count == 0 then
                return nil
            end
            local sorted = table.clone(values)
            table.sort(sorted)
            local mean = 0
            for i, v in sorted do
                mean += (v - mean) / i
            end
            return {
                count = count,
                meanMs = mean,
                p95Ms = sorted[math.max(1, math.ceil(count * 0.95))],
                p99Ms = sorted[math.max(1, math.ceil(count * 0.99))],
                maxMs = sorted[count],
            }
        end,
    }
end
return table.freeze(FrameStats)
