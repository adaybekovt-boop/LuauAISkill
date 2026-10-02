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
