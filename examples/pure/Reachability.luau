--!strict
-- Original reference example. NOT executed in Roblox Studio during pack creation.
-- Host: pure Luau
-- Bounded graph traversal for generated room connectivity; adjacency order belongs to caller.
local Reachability = {}
function Reachability.from(graph: {[string]: {string}}, start: string, maxNodes: number): {[string]: boolean}
    assert(graph[start] ~= nil, "Start node not present")
    assert(maxNodes >= 1 and maxNodes < math.huge and maxNodes % 1 == 0, "Invalid traversal bound")
    local seen: {[string]: boolean} = {[start] = true}
    local queue: {string} = {start}
    local head = 1
    while head <= #queue do
        local node = queue[head]
        head += 1
        for _, neighbor in graph[node] or {} do
            assert(graph[neighbor] ~= nil, "Edge points to an unknown node")
            if not seen[neighbor] then
                assert(#queue < maxNodes, "Traversal bound exceeded")
                seen[neighbor] = true
                table.insert(queue, neighbor)
            end
        end
    end
    return seen
end
return table.freeze(Reachability)
