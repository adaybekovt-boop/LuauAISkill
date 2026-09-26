--!strict
-- Pure match forming (CLI-tested). Entries are grouped oldest-first; the allowed rating gap widens with waiting
-- time so nobody waits forever. Parties are kept together (an entry may represent several players).
-- Status: TYPECHECKED + CLI-EXECUTED.
export type Entry = { key: string, userIds: { number }, rating: number, joinedAt: number }
export type Rules = { matchSize: number, baseGap: number, gapPerSecond: number, maxGap: number }

local QueueLogic = {}

function QueueLogic.allowedGap(rules: Rules, waited: number): number
	return math.min(rules.maxGap, rules.baseGap + rules.gapPerSecond * math.max(0, waited))
end

-- Returns a list of matches (each a list of entries whose player counts sum to matchSize) and leftovers.
function QueueLogic.form(entries: { Entry }, rules: Rules, now: number): ({ { Entry } }, { Entry })
	local pool = table.clone(entries)
	table.sort(pool, function(a: Entry, b: Entry)
		return a.joinedAt < b.joinedAt
	end)
	local used: { [Entry]: boolean } = {}
	local matches = {}
	for _, anchor in pool do
		if used[anchor] or #anchor.userIds > rules.matchSize then
			continue
		end
		local gap = QueueLogic.allowedGap(rules, now - anchor.joinedAt)
		local group, count = { anchor }, #anchor.userIds
		for _, other in pool do
			if count == rules.matchSize then
				break
			end
			if other ~= anchor and not used[other] and count + #other.userIds <= rules.matchSize
				and math.abs(other.rating - anchor.rating) <= gap then
				table.insert(group, other)
				count += #other.userIds
			end
		end
		if count == rules.matchSize then
			for _, e in group do
				used[e] = true
			end
			table.insert(matches, group)
		end
	end
	local leftovers = {}
	for _, e in pool do
		if not used[e] then
			table.insert(leftovers, e)
		end
	end
	return matches, leftovers
end

return table.freeze(QueueLogic)
