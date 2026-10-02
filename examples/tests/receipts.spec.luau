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
local full = { version = 1, coins = 0, sent = 0, received = 0, count = Ledger.LIMIT, receipts = {} :: { [string]: string } }
for i = 1, Ledger.LIMIT do full.receipts[tostring(i)] = "saved" end
assert(Ledger.apply(full, event) == nil, "never evict receipts and regrant old purchases")
print("receipts.spec: atomic grants, duplicate/ambiguous retry, transfer sides, collision, corruption, capacity passed")
