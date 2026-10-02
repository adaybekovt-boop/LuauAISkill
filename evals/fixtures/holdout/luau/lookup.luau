--!strict
type Row = { score: number }
local rows: {[string]: Row} = {}
local function score(name: string): number
    return rows[name].score
end
return score
