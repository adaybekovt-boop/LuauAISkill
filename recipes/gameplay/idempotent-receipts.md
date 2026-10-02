# Idempotent product fulfillment and Robux-transfer receipts

A complete server receipt boundary: one atomic wallet/receipt record, unknown-product deferral, independent
transfer-side accounting, retry-safe transforms, and a bounded shutdown drain. Product receipt decisions use
`Enum.ReceiptDecision`; do not return the legacy `Enum.ProductPurchaseDecision` from these handlers.

Evidence: **TYPECHECKED** (strict, old + new solver, pinned Roblox definitions); pure logic **CLI-EXECUTED**.
**Studio / live: NOT RUN.**

## Architecture
- The server installs three catch-all `MarketplaceService:BindReceiptHandler` handlers before any purchase UI is enabled.
- One DataStore key owns both the purchased-coin balance and permanent receipt IDs. `UpdateAsync` serializes concurrent
  servers and repeats a pure transform; a successful returned record is the only acknowledgement boundary.
- There is no mutable in-memory save snapshot to overwrite another server's grant. Attributes are presentation only.
- Transfer sender and receiver are independent event kinds, each deduped by its own `PurchaseId`; `TransferRequestId`
  correlates the audit entry. Transfer amounts update audit totals, never mint purchased coins.
- `TransferPrompt.request` is server-only and rate-limited. Its request ID proves only that a prompt request was made.
  Offline settlement/parental approval is handled by later receipts, not by the prompt result.

## When NOT to use

do not run this separate wallet alongside a profile that also writes the same coin balance.
For an existing session-locked profile, port the reducer into that owner's atomic save path. It is not a full
shop, currency-spending service, taxation/accounting system, or a transaction across sender and receiver keys.

## Setup and integration
1. Copy `examples/receipts/ServerScriptService` into ServerScriptService. Use a dedicated test universe for DataStore tests.
2. Set the `ReceiptServer` Script's `CoinProductId` attribute to a real developer product owned by this experience.
   The sample maps that one product to 100 coins. Missing/unknown IDs remain pending; there are no sample asset IDs.
3. Disable any competing catch-all handler / legacy receipt owner after explicitly planning migration. Do not
   disconnect the catch-all to enable sales: a receipt without any handler can be auto-acknowledged by Roblox.
4. Your authorized purchase UI can prompt that configured product after this server script is running. Current
   prices belong in platform UI / `GetProductInfoAsync`, never in this reward mapping.
5. To offer a donation, your server interaction handler calls `TransferPrompt.request` with its configured
   recipient and amount after validating the interaction. Never expose those parameters directly from a remote.
   This helper caps the configured amount at 1,000 Robux and prompts at most once per player per 30 seconds.
6. Any future debit must mutate `coins` in the same `UpdateAsync` record. Never spend from `PurchasedCoins` or
   mirror this into an independently saved profile. This example implements fulfillment, not an economy debit API.

## Implementation

### `examples/receipts/ServerScriptService/ReceiptServer.server.luau`

<!-- code: examples/receipts/ServerScriptService/ReceiptServer.server.luau -->
```luau
-- file: examples/receipts/ServerScriptService/ReceiptServer.server.luau
--!strict
-- Dedicated ledger: ALL writers of PurchasedCoins must use this atomic store.
-- Configure the real CoinProductId on this Script before enabling sales. No invented IDs.
local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local Ledger = require(script.Parent.Receipts.Ledger)
local store = DataStoreService:GetDataStore("ReceiptLedger_v1")
local productId = script:GetAttribute("CoinProductId")
local productValid = type(productId) == "number" and productId > 0 and productId % 1 == 0
local closing = false
local active = 0
local connections: { RBXScriptConnection } = {}
local function receive(receipt: { [string]: any }, kind: string): Enum.ReceiptDecision
    if closing then return Enum.ReceiptDecision.NotProcessedYet end
    local userId, id = receipt.PlayerId, receipt.PurchaseId
    if type(userId) ~= "number" or type(id) ~= "string" then return Enum.ReceiptDecision.NotProcessedYet end
    local player = Players:GetPlayerByUserId(userId)
    if not player then return Enum.ReceiptDecision.NotProcessedYet end
    local delta: number
    if kind == "product" then
        if not productValid or receipt.ProductId ~= productId then
            warn("[Receipts] Unknown product; reconcile configuration before retrying")
            return Enum.ReceiptDecision.NotProcessedYet
        end
        delta = 100 -- server-owned reward mapping; never compare CurrencySpent with a list price
    else
        delta = receipt.CurrencySpent -- audit totals ONLY, not a grant of in-experience coins
    end
    local event: Ledger.Event = { id = id, kind = kind, delta = delta,
        transferRequestId = if kind ~= "product" then receipt.TransferRequestId else nil }
    active += 1
    local reason = "request failed"
    local ok, saved = pcall(function()
        return store:UpdateAsync("User_" .. tostring(userId), function(old: any)
            local nextState, why = Ledger.apply(old, event)
            reason = why
            -- No grants, remotes, or yielding inside this retryable transform.
            return nextState, { userId }
        end)
    end)
    active -= 1
    if not ok or saved == nil then
        warn("[Receipts] Deferred:", reason)
        return Enum.ReceiptDecision.NotProcessedYet
    end
    -- Presentation only: never spend from this attribute or another independent profile.
    if player.Parent == Players then
        local shown = player:GetAttribute("PurchasedCoins")
        player:SetAttribute("PurchasedCoins", math.max(saved.coins, if type(shown) == "number" then shown else 0))
    end
    return Enum.ReceiptDecision.Processed
end
-- Catch-all owns unknown products too, preventing accidental auto-acknowledgement.
table.insert(connections, MarketplaceService:BindReceiptHandler(Enum.ReceiptType.DeveloperProduct,
    function(r: { [string]: any }) return receive(r, "product") end))
table.insert(connections, MarketplaceService:BindReceiptHandler(Enum.ReceiptType.RobuxTransferSender,
    function(r: { [string]: any }) return receive(r, "sender") end))
table.insert(connections, MarketplaceService:BindReceiptHandler(Enum.ReceiptType.RobuxTransferReceiver,
    function(r: { [string]: any }) return receive(r, "receiver") end))
local function load(player: Player)
    local ok, value = pcall(function() return store:GetAsync("User_" .. tostring(player.UserId)) end)
    if ok and type(value) == "table" and type(value.coins) == "number" and player.Parent == Players then
        -- Concurrent receipt callbacks may already have published a newer total.
        local shown = player:GetAttribute("PurchasedCoins")
        player:SetAttribute("PurchasedCoins", math.max(value.coins, if type(shown) == "number" then shown else 0))
    end
end
Players.PlayerAdded:Connect(load)
for _, player in Players:GetPlayers() do task.spawn(load, player) end
game:BindToClose(function()
    closing = true
    local deadline = os.clock() + 25
    while active > 0 and os.clock() < deadline do task.wait(0.1) end
    for _, connection in connections do connection:Disconnect() end
end)
```
<!-- /code -->

### `examples/receipts/ServerScriptService/Receipts/Ledger.luau`

<!-- code: examples/receipts/ServerScriptService/Receipts/Ledger.luau -->
```luau
-- file: examples/receipts/ServerScriptService/Receipts/Ledger.luau
--!strict
-- Pure atomic receipt reducer. Never trims dedupe history; exhaustion fails closed.
export type Event = { id: string, kind: string, delta: number, transferRequestId: string? }
export type State = { version: number, coins: number, sent: number, received: number,
    count: number, receipts: { [string]: string } }
local Ledger = {}
Ledger.LIMIT = 1000
local function integer(v: any): boolean
    return type(v) == "number" and v == v and v >= 0 and v <= 9007199254740991 and v % 1 == 0
end
function Ledger.apply(old: any, event: Event): (State?, string)
    if #event.id < 1 or #event.id > 200 or not integer(event.delta) then return nil, "invalid" end
    if event.kind ~= "product" and event.kind ~= "sender" and event.kind ~= "receiver" then
        return nil, "invalid"
    end
    if event.kind ~= "product" and (not event.transferRequestId or #event.transferRequestId > 200
        or #event.transferRequestId == 0) then return nil, "invalid" end
    local state: State
    if old == nil then
        state = { version = 1, coins = 0, sent = 0, received = 0, count = 0, receipts = {} }
    else
        if type(old) ~= "table" or old.version ~= 1 or not integer(old.coins)
            or not integer(old.sent) or not integer(old.received) or not integer(old.count)
            or type(old.receipts) ~= "table" then return nil, "corrupt" end
        local receipts: { [string]: string } = {}
        local count = 0
        for k, v in old.receipts do
            if type(k) ~= "string" or type(v) ~= "string" or #k > 210 or #v > 230 then return nil, "corrupt" end
            receipts[k] = v
            count += 1
        end
        if count ~= old.count or count > Ledger.LIMIT then return nil, "corrupt" end
        state = { version = 1, coins = old.coins, sent = old.sent, received = old.received,
            count = count, receipts = receipts }
    end
    local key = event.kind .. ":" .. event.id
    local stamp = tostring(event.delta) .. ":" .. (event.transferRequestId or "")
    if state.receipts[key] then
        return if state.receipts[key] == stamp then state else nil,
            if state.receipts[key] == stamp then "duplicate" else "collision"
    end
    if state.count >= Ledger.LIMIT then return nil, "full" end
    local field = if event.kind == "product" then "coins" elseif event.kind == "sender" then "sent" else "received"
    if field == "coins" then state.coins += event.delta
    elseif field == "sent" then state.sent += event.delta
    else state.received += event.delta end
    if not integer(state.coins) or not integer(state.sent) or not integer(state.received) then return nil, "overflow" end
    state.receipts[key] = stamp
    state.count += 1
    return state, "granted"
end
return Ledger
```
<!-- /code -->

### `examples/receipts/ServerScriptService/Receipts/TransferPrompt.luau`

<!-- code: examples/receipts/ServerScriptService/Receipts/TransferPrompt.luau -->
```luau
-- file: examples/receipts/ServerScriptService/Receipts/TransferPrompt.luau
--!strict
-- Optional server-only entry point for your existing, rate-limited interaction UI.
-- Caller supplies a server-configured recipient and amount, never a client supplied pair.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local nextPrompt: { [Player]: number } = {}
Players.PlayerRemoving:Connect(function(player) nextPrompt[player] = nil end)
local TransferPrompt = {}
function TransferPrompt.request(sender: Player, configuredRecipient: number, configuredAmount: number): (boolean, string?)
    if sender.Parent ~= Players or configuredRecipient == sender.UserId
        or configuredRecipient <= 0 or configuredRecipient > 9007199254740991 or configuredRecipient % 1 ~= 0
        or configuredAmount <= 0 or configuredAmount > 1000 or configuredAmount % 1 ~= 0
        or configuredRecipient ~= configuredRecipient or configuredAmount ~= configuredAmount then return false, nil end
    local now = os.clock()
    if now < (nextPrompt[sender] or 0) then return false, nil end
    nextPrompt[sender] = now + 30
    local ok, result = pcall(function()
        return MarketplaceService:PromptRobuxTransferAsync(sender, configuredRecipient, configuredAmount)
    end)
    -- Request ID is NOT settlement. Sender/receiver receipts are handled independently.
    return ok, if ok then result else nil
end
return TransferPrompt
```
<!-- /code -->

## How to test

| Scenario | Required observation |
|---|---|
| CLI duplicate/retry | Same PurchaseId applies once; ambiguous committed write followed by retry does not regrant |
| Studio, two server delivery simulation | Invoke the reducer/store adapter on the same test key concurrently; balance changes exactly once |
| Studio save failure / unknown product | Decision remains NotProcessedYet, no default record on failed read, no prompt-close grant |
| Rejoin after failed/ambiguous acknowledgement | Stored receipt is found and acknowledged without another reward |
| Transfer receipt sides in either order | Separate sender/receiver audit totals; no in-game reward from prompt return |
| Player leaves during UpdateAsync | Durable result still safe to acknowledge; no writes to a departed player's presentation |
| Corrupt / full record | No overwrite, no acknowledgement, actionable log for reconciliation |

Studio purchase simulation is not evidence of real settlement. Real transfer/purchase testing can move real Robux;
use an explicitly authorized test and record LIVE TESTED separately.

## Failure paths and limits
Receipts are never evicted: deleting a receipt ID permits a delayed duplicate to grant again. This bounded
example fails closed at 1,000 receipts and rejects malformed/newer records. Alert on capacity well before that
point, disable new sales if necessary, and design a reviewed archival/migration scheme; blindly rotating store
names loses dedupe. Payload-length caps and the count cap keep this representation below the 4 MB value limit,
but existing corrupt records are refused. Return failures promptly rather than retrying forever inside a handler.
Roblox redelivers unresolved receipts on later purchase/join, not on a guaranteed periodic timer.
A ProductId catalog is versioned business logic: preserve mappings for products that still have pending receipts.
The read-on-join attribute may be stale; it is explicitly non-authoritative.

## Verification
From the skill directory, run `python tools/check_all.py`. Pure tests for this recipe:
`luau examples/tests/receipts.spec.luau`. The checker runs both Luau solvers. Engine coverage remains NOT RUN until you retain
assertion output from the specified Studio scenario with Studio build, place revision, peers, and device.

Sources: cd:production/monetization/developer-products, cd:production/monetization/robux-transfers, cd:reference/engine/classes/MarketplaceService, cd:reference/engine/classes/GlobalDataStore, api:MarketplaceService.BindReceiptHandler, api:MarketplaceService.PromptRobuxTransferAsync.
