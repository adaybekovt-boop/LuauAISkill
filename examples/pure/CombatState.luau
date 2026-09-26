--!strict
-- Original reference example. NOT executed in Roblox Studio during pack creation.
-- Host: pure Luau
-- Small gameplay state machine. No hit detection, damage, networking or real-world instruction.
export type Phase = "Idle" | "Windup" | "Active" | "Recovery" | "Stunned" | "Dead"
export type State = {phase: Phase, untilTime: number, actionId: number}
local CombatState = {}
local function checkedTime(now: number): ()
    assert(now == now and math.abs(now) < math.huge, "Expected trusted finite time")
end
function CombatState.initial(): State
    return {phase = "Idle", untilTime = 0, actionId = 0}
end
function CombatState.requestAttack(state: State, now: number): (State, boolean)
    checkedTime(now)
    if state.phase ~= "Idle" then
        return state, false
    end
    -- Durations are illustrative game-design values, not Roblox limits.
    return {phase = "Windup", untilTime = now + 0.3, actionId = state.actionId + 1}, true
end
function CombatState.step(state: State, now: number): State
    checkedTime(now)
    if state.phase == "Dead" or state.phase == "Idle" or now < state.untilTime then
        return state
    end
    if state.phase == "Windup" then
        return {phase = "Active", untilTime = now + 0.15, actionId = state.actionId}
    elseif state.phase == "Active" then
        return {phase = "Recovery", untilTime = now + 0.45, actionId = state.actionId}
    end
    return {phase = "Idle", untilTime = now, actionId = state.actionId}
end
function CombatState.kill(state: State): State
    return {phase = "Dead", untilTime = 0, actionId = state.actionId}
end
-- Intentional: step makes at most one transition, even for a large dt.
-- Production timing and rollback require a defined simulation policy.
return table.freeze(CombatState)
