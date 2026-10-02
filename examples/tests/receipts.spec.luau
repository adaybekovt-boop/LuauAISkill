--!strict
local Ledger = require("../receipts/ServerScriptService/Receipts/Ledger")
local event: Ledger.Event = { id = "purchase-A", kind = "product", delta = 100 }
local a, reason = Ledger.apply(nil, event)
assert(a and reason == "granted" and a.coins == 100)
local b, duplicate = Ledger.apply(a, event)
assert(b and duplicate == "duplicate" and b.coins == 100 and b.count == 1)
assert(a ~= b and a.receipts ~= b.receipts, "transform must not mutate old state")
-- Ambiguous save error followed by retry: committed state must still dedupe.
local committed = b
local retry = Ledger.apply(committed, event)
assert(retry and retry.coins == 100)
local sender = Ledger.apply(retry, { id = "transfer-A", kind = "sender", delta = 25, transferRequestId = "request-A" })
assert(sender and sender.sent == 25 and sender.coins == 100)
local receiver = Ledger.apply(sender, { id = "transfer-A", kind = "receiver", delta = 25, transferRequestId = "request-A" })
assert(receiver and receiver.received == 25 and receiver.count == 3)
assert(Ledger.apply(receiver, { id = "purchase-A", kind = "product", delta = 200 }) == nil)
assert(Ledger.apply("corrupt", event) == nil)
assert(Ledger.apply(nil, { id = "x", kind = "product", delta = 0/0 }) == nil)
assert(Ledger.apply(nil, { id = "x", kind = "sender", delta = 25 }) == nil)
-- A purchase after the former arbitrary cap must still grant. Retain the oldest ID.
local history: Ledger.State? = nil
for i = 1, 1501 do
	local nextState, why = Ledger.apply(history, { id = "purchase-" .. tostring(i), kind = "product", delta = 1 })
	assert(nextState and why == "granted", "purchase history must not have a 1000-receipt cutoff")
	history = nextState
end
assert(history and history.count == 1501 and history.coins == 1501)
local replay, replayReason = Ledger.apply(history, { id = "purchase-1", kind = "product", delta = 1 })
assert(replay and replayReason == "duplicate" and replay.count == 1501 and replay.coins == 1501)

-- Model UpdateAsync optimistic conflicts: discarded candidates have no side effects.
local competingA = Ledger.apply(history, { id = "concurrent-A", kind = "product", delta = 2 })
local competingB = Ledger.apply(history, { id = "concurrent-B", kind = "product", delta = 3 })
assert(competingA and competingB and history.coins == 1501)
local rebasedB = Ledger.apply(competingA, { id = "concurrent-B", kind = "product", delta = 3 })
assert(rebasedB and rebasedB.coins == 1506 and rebasedB.count == 1503)
local sameReceiptRetry, sameReason = Ledger.apply(competingA, { id = "concurrent-A", kind = "product", delta = 2 })
assert(sameReceiptRetry and sameReason == "duplicate" and sameReceiptRetry.coins == 1503)

-- A failed write discards the candidate: a fresh retry must still grant exactly once.
local failedCandidate = Ledger.apply(history, { id = "failed-save", kind = "product", delta = 7 })
assert(failedCandidate and history.receipts["product:failed-save"] == nil)
local afterFailure, failureReason = Ledger.apply(history, { id = "failed-save", kind = "product", delta = 7 })
assert(afterFailure and failureReason == "granted" and afterFailure.coins == 1508)
local overflowState = { version = 1, coins = 9007199254740991, sent = 0, received = 0, count = 0, receipts = {} }
local overflow, overflowReason = Ledger.apply(overflowState, event)
assert(overflow == nil and overflowReason == "overflow" and overflowState.count == 0)
local malformed = { version = 1, coins = 0, sent = 0, received = 0, count = 1, receipts = {} }
assert(Ledger.apply(malformed, event) == nil, "inconsistent persisted count must fail closed")
print("receipts.spec: grants, retries, transfer sides, collisions, corruption, >1500 receipts, conflicts, failures, overflow passed")
