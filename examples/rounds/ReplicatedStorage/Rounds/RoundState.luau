--!strict
-- Pure round state machine (no Roblox APIs; CLI-tested in examples/tests/rounds.spec.luau).
--   Waiting (not enough players) → Intermission (countdown) → InRound (timer / last one standing) → Results → …
-- The server calls step() a few times per second with facts; it returns the phase change (if any).
-- Status: TYPECHECKED + CLI-EXECUTED.
export type Phase = "Waiting" | "Intermission" | "InRound" | "Results"
export type Config = {
	minPlayers: number,
	intermission: number,
	roundLength: number,
	results: number,
	endWhenAliveAtMost: number, -- 1 = last one standing; 0 = only the timer ends the round
}
export type Round = { phase: Phase, endsAt: number, config: Config, winner: string? }
export type Facts = { now: number, players: number, alive: number, lastAlive: string? }

local RoundState = {}

function RoundState.new(config: Config, now: number): Round
	return { phase = "Waiting", endsAt = now, config = config, winner = nil }
end

local function go(r: Round, phase: Phase, now: number, duration: number): Phase
	r.phase = phase
	r.endsAt = now + duration
	return phase
end

-- Returns the new phase when it changed, otherwise nil.
function RoundState.step(r: Round, f: Facts): Phase?
	local c = r.config
	if r.phase == "Waiting" then
		if f.players >= c.minPlayers then
			return go(r, "Intermission", f.now, c.intermission)
		end
	elseif r.phase == "Intermission" then
		if f.players < c.minPlayers then
			return go(r, "Waiting", f.now, 0) -- someone left during the countdown
		elseif f.now >= r.endsAt then
			r.winner = nil
			return go(r, "InRound", f.now, c.roundLength)
		end
	elseif r.phase == "InRound" then
		local lastStanding = c.endWhenAliveAtMost > 0 and f.alive <= c.endWhenAliveAtMost
		if lastStanding or f.now >= r.endsAt then
			r.winner = if lastStanding and f.alive == 1 then f.lastAlive else nil
			return go(r, "Results", f.now, c.results)
		end
	elseif r.phase == "Results" then
		if f.now >= r.endsAt then
			return if f.players >= c.minPlayers then go(r, "Intermission", f.now, c.intermission)
				else go(r, "Waiting", f.now, 0)
		end
	end
	return nil
end

return table.freeze(RoundState)
