--!strict
-- Pure UpdateAsync transforms for session-locked profiles. No Roblox APIs → tested in the Luau CLI
-- (examples/tests/data.spec.luau). Each transform returns (newValue, status); newValue == nil aborts the write.
-- Transforms may run several times per request and must not yield (UpdateAsync contract).
-- Status: TYPECHECKED + CLI-EXECUTED.
export type Lock = { id: string, time: number }
export type Stored = { data: any, lock: Lock? }
export type AcquireStatus = "ok" | "locked" | "corrupt"
export type SaveStatus = "ok" | "lost"

local SessionLock = {}

-- Take the lock if the key is new, unlocked, ours, or the lock is older than `expiry` seconds (dead server).
function SessionLock.acquire(old: unknown, lockId: string, now: number, expiry: number,
	makeDefault: () -> any): (Stored?, AcquireStatus)
	if old ~= nil and (type(old) ~= "table" or (old :: any).data == nil) then
		return nil, "corrupt" -- never overwrite a value we don't understand
	end
	local stored: Stored = if old ~= nil then old :: Stored else { data = makeDefault() }
	local lock = stored.lock
	if lock and lock.id ~= lockId and now - lock.time < expiry then
		return nil, "locked"
	end
	stored.lock = { id = lockId, time = now }
	return stored, "ok"
end

-- Write `data` only while we still own the lock; refreshes the lock time (autosave keeps the lock alive).
function SessionLock.save(old: unknown, lockId: string, now: number, data: any): (Stored?, SaveStatus)
	if type(old) ~= "table" then
		return nil, "lost"
	end
	local stored = old :: Stored
	if not stored.lock or stored.lock.id ~= lockId then
		return nil, "lost" -- another server took over (our lock expired): our copy is stale, don't write it
	end
	stored.data = data
	stored.lock = { id = lockId, time = now }
	return stored, "ok"
end

-- Final save + unlock (player left / server closing).
function SessionLock.release(old: unknown, lockId: string, data: any): (Stored?, SaveStatus)
	local stored: Stored?, status: SaveStatus = SessionLock.save(old, lockId, 0, data)
	if stored then
		stored.lock = nil
	end
	return stored, status
end

return table.freeze(SessionLock)
