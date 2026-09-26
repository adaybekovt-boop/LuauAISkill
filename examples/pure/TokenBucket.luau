--!strict
-- Original reference example. NOT executed in Roblox Studio during pack creation.
-- Host: pure Luau
-- Bounded rate limiter with explicit injected clock and no remote-controlled keys.
export type Bucket = {
    take: (now: number, cost: number?) -> boolean,
    available: (now: number) -> number,
}
local function finite(n: number): boolean
    return n == n and n > -math.huge and n < math.huge
end
local TokenBucket = {}
function TokenBucket.new(capacity: number, refillPerSecond: number, startTime: number): Bucket
    assert(finite(capacity) and capacity > 0, "capacity must be finite and positive")
    assert(finite(refillPerSecond) and refillPerSecond >= 0, "refill must be finite and nonnegative")
    assert(finite(startTime), "startTime must be finite")
    local tokens = capacity
    local lastTime = startTime
    local function refill(now: number): ()
        assert(finite(now), "Use a trusted finite clock")
        local elapsed = math.max(0, now - lastTime)
        lastTime = math.max(lastTime, now)
        if refillPerSecond > 0 and elapsed > 0 then
            tokens = math.min(capacity, tokens + elapsed * refillPerSecond)
        end
    end
    return {
        take = function(now: number, cost: number?): boolean
            local charge = if cost == nil then 1 else cost
            if not finite(charge) or charge <= 0 or charge > capacity then
                return false
            end
            refill(now)
            if tokens < charge then
                return false
            end
            tokens -= charge
            return true
        end,
        available = function(now: number): number
            refill(now)
            return tokens
        end,
    }
end
return table.freeze(TokenBucket)
