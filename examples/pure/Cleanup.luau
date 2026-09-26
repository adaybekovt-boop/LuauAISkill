--!strict
-- Original reference example. NOT executed in Roblox Studio during pack creation.
-- Host: pure Luau
-- Own cleanup callbacks; reverse order; re-entrant destruction; aggregates errors.
export type Scope = {
    add: (callback: () -> ()) -> (),
    destroy: () -> {string},
    isDestroyed: () -> boolean,
}
local Cleanup = {}
function Cleanup.new(): Scope
    local callbacks: {() -> ()} = {}
    local errors: {string} = {}
    local destroyed = false
    local function run(callback: () -> ()): ()
        local ok, err = pcall(callback)
        if not ok then
            table.insert(errors, tostring(err))
        end
    end
    local function errorSnapshot(): {string}
        local result: {string} = {}
        for _, message in errors do
            table.insert(result, message)
        end
        return result
    end
    return {
        add = function(callback: () -> ()): ()
            if destroyed then
                run(callback)
            else
                table.insert(callbacks, callback)
            end
        end,
        destroy = function(): {string}
            if not destroyed then
                destroyed = true -- before callbacks: recursive destroy is safe
                local owned = callbacks
                callbacks = {}
                for i = #owned, 1, -1 do
                    run(owned[i])
                end
            end
            return errorSnapshot()
        end,
        isDestroyed = function(): boolean
            return destroyed
        end,
    }
end
return table.freeze(Cleanup)
