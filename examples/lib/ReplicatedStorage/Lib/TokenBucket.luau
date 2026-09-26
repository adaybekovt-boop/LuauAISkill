--!strict
-- TokenBucket: per-key rate limiter (burst `capacity`, sustained `rate` tokens/second).
-- Pure Luau; inject the clock so it is testable. Keys must come from a fixed set (never raw client strings).
-- Status: TYPECHECKED + CLI-EXECUTED (examples/tests/lib.spec.luau).

export type Limit = { capacity: number, rate: number }
export type Limiter<K> = {
	allow: (self: Limiter<K>, key: K, action: string, now: number, cost: number?) -> boolean,
	forget: (self: Limiter<K>, key: K) -> (),
}

type Bucket = { tokens: number, last: number }

local TokenBucket = {}

function TokenBucket.new<K>(limits: { [string]: Limit }): Limiter<K>
	for action, l in limits do
		assert(l.capacity > 0 and l.rate >= 0 and l.capacity == l.capacity, "invalid limit for " .. action)
	end
	local buckets: { [K]: { [string]: Bucket } } = {}
	local limiter = {}

	function limiter.allow(_self: Limiter<K>, key: K, action: string, now: number, cost: number?): boolean
		local limit = limits[action]
		if limit == nil or now ~= now then
			return false -- unknown action names never allocate state
		end
		local c = cost or 1
		if c ~= c or c <= 0 or c > limit.capacity then
			return false
		end
		local perKey = buckets[key]
		if perKey == nil then
			perKey = {}
			buckets[key] = perKey
		end
		local b = perKey[action]
		if b == nil then
			b = { tokens = limit.capacity, last = now }
			perKey[action] = b
		end
		local elapsed = math.max(0, now - b.last)
		b.last = math.max(b.last, now)
		b.tokens = math.min(limit.capacity, b.tokens + elapsed * limit.rate)
		if b.tokens < c then
			return false
		end
		b.tokens -= c
		return true
	end

	function limiter.forget(_self: Limiter<K>, key: K)
		buckets[key] = nil
	end

	return limiter :: any
end

return TokenBucket
