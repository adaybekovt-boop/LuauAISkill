--!strict
-- Original reference example. NOT executed in Roblox Studio during pack creation.
-- Host: pure Luau
-- Explicit tagged outcomes; runtime validation remains the caller's responsibility.
export type Result<T> = {ok: true, value: T} | {ok: false, error: string}
local Result = {}
function Result.success<T>(value: T): Result<T>
    return {ok = true, value = value}
end
function Result.failure(message: string): Result<never>
    return {ok = false, error = message}
end
return table.freeze(Result)
