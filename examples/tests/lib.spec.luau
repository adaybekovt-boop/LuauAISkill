--!strict
-- Unit tests for pure library modules. Run: luau examples/tests/lib.spec.luau (from repo root).
local TokenBucket = require("../lib/ReplicatedStorage/Lib/TokenBucket")
local Validate = require("../lib/ReplicatedStorage/Lib/Validate")
local Signal = require("../lib/ReplicatedStorage/Lib/Signal")
local Spring = require("../lib/ReplicatedStorage/Lib/Spring")
local Hash = require("../lib/ReplicatedStorage/Lib/Hash")

local passed, failed = 0, 0
local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end
local function eq(a: any, b: any, msg: string?)
	if a ~= b then
		error(`{msg or "expected equal"}: {tostring(a)} ~= {tostring(b)}`, 2)
	end
end

test("TokenBucket burst then refill", function()
	local lim = TokenBucket.new({ Fire = { capacity = 3, rate = 1 } })
	eq(lim:allow("p1", "Fire", 0), true)
	eq(lim:allow("p1", "Fire", 0), true)
	eq(lim:allow("p1", "Fire", 0), true)
	eq(lim:allow("p1", "Fire", 0), false, "4th in burst")
	eq(lim:allow("p1", "Fire", 1.01), true, "refilled one token")
	eq(lim:allow("p2", "Fire", 0), true, "independent key")
end)
test("TokenBucket rejects unknown actions, NaN time and bad cost", function()
	local lim = TokenBucket.new({ Use = { capacity = 2, rate = 1 } })
	eq(lim:allow("p", "Nope", 0), false)
	eq(lim:allow("p", "Use", 0 / 0), false)
	eq(lim:allow("p", "Use", 0, 0 / 0), false)
	eq(lim:allow("p", "Use", 0, 5), false)
end)
test("TokenBucket clock going backwards doesn't mint tokens", function()
	local lim = TokenBucket.new({ Use = { capacity = 1, rate = 1 } })
	eq(lim:allow("p", "Use", 10), true)
	eq(lim:allow("p", "Use", 5), false)
	eq(lim:allow("p", "Use", 10.5), false)
	eq(lim:allow("p", "Use", 11.01), true)
end)
test("Validate numbers", function()
	eq(Validate.number(5, 0, 10), 5)
	eq(Validate.number(0 / 0, 0, 10), nil, "NaN")
	eq(Validate.number(math.huge, 0, 10), nil, "inf")
	eq(Validate.number("5", 0, 10), nil, "string")
	eq(Validate.integer(2.5, 0, 10), nil, "fraction")
	eq(Validate.integer(3, 0, 10), 3)
end)
test("Validate strings and sets", function()
	eq(Validate.string("abc", 5), "abc")
	eq(Validate.string("abcdef", 5), nil)
	eq(Validate.string("\255\255", 5), nil, "invalid utf8")
	eq(Validate.string("abc", 5, "^%a+$"), "abc")
	eq(Validate.string("ab1", 5, "^%a+$"), nil)
	eq(Validate.oneOf("Light", { Light = true, Heavy = true }), "Light")
	eq(Validate.oneOf("__index", { Light = true }), nil)
	eq(Validate.boolean(false), false)
	eq(Validate.boolean(0), nil)
end)
test("Signal connect/once/disconnect/error isolation", function()
	local s = Signal.new() :: Signal.Signal<number>
	local total = 0
	local c1 = s:connect(function(n) total += n end)
	s:once(function(n) total += n * 10 end)
	s:connect(function() error("boom") end)
	s:fire(1)
	eq(total, 11)
	s:fire(1)
	eq(total, 12, "once fired only once")
	c1:disconnect()
	s:fire(1)
	eq(total, 12, "disconnected")
end)
test("Spring converges to target without overshoot when critically damped", function()
	local sp = Spring.new(4, 1)
	sp.target = 1
	local maxPos = 0
	for _ = 1, 240 do
		maxPos = math.max(maxPos, Spring.step(sp, 1 / 60))
	end
	assert(math.abs(sp.position - 1) < 1e-3, "converged: " .. sp.position)
	assert(maxPos < 1.02, "overshoot " .. maxPos)
end)
test("Spring is stable at low frame rate", function()
	local sp = Spring.new(8, 0.5)
	sp.target = 1
	for _ = 1, 100 do
		Spring.step(sp, 0.5) -- clamped internally
	end
	assert(sp.position == sp.position and math.abs(sp.position) < 10, "diverged")
end)
test("Hash.mul32 matches reference", function()
	local function ref(a: number, b: number): number
		local r = 0
		for i = 0, 31 do
			if bit32.btest(b, 2 ^ i) then
				r = (r + (a * 2 ^ i) % 4294967296) % 4294967296
			end
		end
		return r
	end
	for _, v in { { 1, 2 }, { 123456789, 0x45d9f3b }, { 4294967295, 4294967295 }, { 2 ^ 31, 3 }, { 65537, 65535 } } do
		eq(Hash.mul32(v[1], v[2]), ref(v[1], v[2]))
	end
end)
test("Hash is deterministic, order-sensitive and spreads", function()
	eq(Hash.hash3(1, 2, 3), Hash.hash3(1, 2, 3))
	assert(Hash.hash3(1, 2, 3) ~= Hash.hash3(3, 2, 1), "order")
	assert(Hash.hash3(-1, 0, 0) == Hash.hash3(4294967295, 0, 0), "negative wrap")
	local buckets = table.create(10, 0)
	for i = 1, 10000 do
		local b = math.floor(Hash.unit(i, 7, 13) * 10) + 1
		buckets[b] += 1
	end
	for i = 1, 10 do
		assert(buckets[i] > 850 and buckets[i] < 1150, "bucket " .. i .. " = " .. buckets[i])
	end
end)

print(`lib.spec: {passed} passed, {failed} failed`)
if failed > 0 then
	error("tests failed")
end
