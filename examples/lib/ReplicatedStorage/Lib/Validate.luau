--!strict
-- Validate: runtime checks for untrusted values (remote payloads, attributes, JSON). Types don't validate data.
-- Every function returns the refined value or nil. Pure except typeof(), which also works in the Luau CLI.
-- Status: TYPECHECKED + CLI-EXECUTED for number/string/enum helpers (examples/tests/lib.spec.luau).

local Validate = {}

function Validate.finite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

function Validate.number(v: unknown, min: number, max: number): number?
	if type(v) ~= "number" or v ~= v or v < min or v > max then
		return nil
	end
	return v
end

function Validate.integer(v: unknown, min: number, max: number): number?
	local n = Validate.number(v, min, max)
	if n == nil or n % 1 ~= 0 then
		return nil
	end
	return n
end

function Validate.string(v: unknown, maxLen: number, pattern: string?): string?
	if type(v) ~= "string" or #v > maxLen or utf8.len(v) == nil then
		return nil
	end
	if pattern and not string.match(v, pattern) then
		return nil
	end
	return v
end

-- Membership in a fixed set: Validate.oneOf(v, { Light = true, Heavy = true })
function Validate.oneOf<T>(v: unknown, allowed: { [T]: boolean }): T?
	if v == nil then
		return nil
	end
	if (allowed :: any)[v] == true then
		return v :: any
	end
	return nil
end

function Validate.boolean(v: unknown): boolean?
	if type(v) == "boolean" then
		return v
	end
	return nil
end

function Validate.vector3(v: unknown, maxMagnitude: number): Vector3?
	if typeof(v) ~= "Vector3" then
		return nil
	end
	local vec = v :: Vector3
	if not (Validate.finite(vec.X) and Validate.finite(vec.Y) and Validate.finite(vec.Z)) then
		return nil
	end
	if vec.Magnitude > maxMagnitude then
		return nil
	end
	return vec
end

function Validate.unitVector(v: unknown, tolerance: number?): Vector3?
	local vec = Validate.vector3(v, 1 + (tolerance or 0.01))
	if vec == nil or math.abs(vec.Magnitude - 1) > (tolerance or 0.01) then
		return nil
	end
	return vec
end

-- Instance of a class that lives under an expected ancestor (e.g. workspace.Interactables).
function Validate.instanceOf(v: unknown, className: string, ancestor: Instance?): Instance?
	if typeof(v) ~= "Instance" then
		return nil
	end
	local inst = v :: Instance
	if not inst:IsA(className) then
		return nil
	end
	if ancestor and not inst:IsDescendantOf(ancestor) then
		return nil
	end
	return inst
end

return table.freeze(Validate)
