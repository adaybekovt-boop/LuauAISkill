--!strict
local Protocol = require("../regression/ReplicatedStorage/Regression/Protocol")
assert(Protocol.complete({ 1, 2 }, { [1] = "ready", [2] = "ready" }, "ready"))
assert(not Protocol.complete({ 1, 2 }, { [1] = "ready" }, "ready"))
assert(not Protocol.complete({ 1 }, { [1] = "old-phase" }, "ready"))
local result = Protocol.result({ { name = "ok", ok = true, detail = "observed" },
	{ name = "timeout", ok = false, detail = "missing peer" } })
assert(result.passed == 1 and result.failed == 1 and #result.assertions == 2)
print("regression.spec: all-peer barrier, stale acknowledgment and structured failure passed")
