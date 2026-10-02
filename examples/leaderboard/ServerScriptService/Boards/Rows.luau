--!strict
export type Row = { userId: number, score: number }
local Rows = {}
function Rows.valid(value: any): boolean
    return type(value) == "number" and value == value and value >= 0 and value <= 2147483647 and value % 1 == 0
end
function Rows.sorted(entries: { [string]: any }, limit: number): { Row }
    local rows: { Row } = {}
    for key, entry in entries do
        local id = tonumber(key)
        if id and id > 0 and id % 1 == 0 and type(entry) == "table" and Rows.valid(entry.value) then
            table.insert(rows, { userId = id, score = entry.value })
        end
    end
    table.sort(rows, function(a: Row, b: Row) return a.score > b.score or (a.score == b.score and a.userId < b.userId) end)
    while #rows > limit do table.remove(rows) end
    return rows
end
function Rows.keys(userId: number, friends: { number }): ({ string }, boolean)
    local ids: { number } = {}
    local seen: { [number]: boolean } = { [userId] = true }
    for _, id in friends do
        if id > 0 and id % 1 == 0 and id == id and not seen[id] then
            seen[id] = true; table.insert(ids, id)
        end
    end
    table.sort(ids)
    local keys = { tostring(userId) }
    for i = 1, math.min(99, #ids) do table.insert(keys, tostring(ids[i])) end
    return keys, #ids > 99
end
return Rows
