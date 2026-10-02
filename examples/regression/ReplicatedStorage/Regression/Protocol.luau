--!strict
export type Receipt = { name: string, ok: boolean, detail: string }
local Protocol = {}
function Protocol.complete(expected: { number }, acknowledgments: { [number]: string }, phase: string): boolean
	for _, userId in expected do if acknowledgments[userId] ~= phase then return false end end
	return true
end
function Protocol.result(rows: { Receipt }): { passed: number, failed: number, assertions: { Receipt } }
	local passed, failed = 0, 0
	for _, row in rows do if row.ok then passed += 1 else failed += 1 end end
	return { passed = passed, failed = failed, assertions = rows }
end
return Protocol
