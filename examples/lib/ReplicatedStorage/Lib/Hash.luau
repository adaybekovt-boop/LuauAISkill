--!strict
-- Hash: deterministic 32-bit integer hashing for seeds (procedural generation). Identical on every machine.
-- mul32 keeps every partial product < 2^53 so doubles stay exact.
-- Status: TYPECHECKED + CLI-EXECUTED (reference-checked multiplication).

local Hash = {}

local TWO32 = 4294967296

function Hash.mul32(a: number, b: number): number
	local aLo, aHi = a % 65536, a // 65536
	local bLo, bHi = b % 65536, b // 65536
	return ((aHi * bLo + aLo * bHi) % 65536 * 65536 + aLo * bLo) % TWO32
end

local function mix(h: number): number
	h = bit32.bxor(h, bit32.rshift(h, 16))
	h = Hash.mul32(h, 0x45d9f3b)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	h = Hash.mul32(h, 0x45d9f3b)
	return bit32.bxor(h, bit32.rshift(h, 16))
end

-- Combine up to three integers (negative values are wrapped into 0..2^32-1).
function Hash.hash3(a: number, b: number, c: number): number
	local x = bit32.bxor(a % TWO32, bit32.lrotate(b % TWO32, 16), bit32.lrotate(c % TWO32, 8))
	return mix(x)
end

-- Uniform float in [0, 1) from integer inputs (stateless noise for per-cell decisions).
function Hash.unit(a: number, b: number, c: number): number
	return Hash.hash3(a, b, c) / TWO32
end

return table.freeze(Hash)
