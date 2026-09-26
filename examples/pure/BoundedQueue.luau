--!strict
-- Original reference example. NOT executed in Roblox Studio during pack creation.
-- Host: pure Luau
-- Fixed-capacity FIFO; overflow returns false, never creates an unbounded backlog.
export type Queue<T> = {
    push: (value: T) -> boolean,
    pop: () -> T?,
    size: () -> number,
    clear: () -> (),
}
local BoundedQueue = {}
function BoundedQueue.new<T>(capacity: number): Queue<T>
    assert(capacity > 0 and capacity < math.huge and capacity % 1 == 0, "Positive finite integer capacity required")
    local storage: {[number]: T?} = {}
    local head, count = 1, 0
    return {
        push = function(value: T): boolean
            assert(value ~= nil, "nil is reserved for an empty queue")
            if count == capacity then
                return false
            end
            local index = ((head - 1 + count) % capacity) + 1
            storage[index] = value
            count += 1
            return true
        end,
        pop = function(): T?
            if count == 0 then
                return nil
            end
            local value = storage[head]
            storage[head] = nil
            head = (head % capacity) + 1
            count -= 1
            return value
        end,
        size = function(): number
            return count
        end,
        clear = function(): ()
            table.clear(storage)
            head, count = 1, 0
        end,
    }
end
return table.freeze(BoundedQueue)
