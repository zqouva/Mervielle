--!strict

-->	["sha256"]
-->	Binary sha256 digest helper.
-->	This exists so the vault layer can authenticate sealed records instead of only
-->	encrypting them. It is also exposed for callers that want a stronger digest
-->	than the small hash32 helper.

local SHA256 = {}

local WORD = 4294967296

local K = {
	0x428A2F98,
	0x71374491,
	0xB5C0FBCF,
	0xE9B5DBA5,
	0x3956C25B,
	0x59F111F1,
	0x923F82A4,
	0xAB1C5ED5,
	0xD807AA98,
	0x12835B01,
	0x243185BE,
	0x550C7DC3,
	0x72BE5D74,
	0x80DEB1FE,
	0x9BDC06A7,
	0xC19BF174,
	0xE49B69C1,
	0xEFBE4786,
	0x0FC19DC6,
	0x240CA1CC,
	0x2DE92C6F,
	0x4A7484AA,
	0x5CB0A9DC,
	0x76F988DA,
	0x983E5152,
	0xA831C66D,
	0xB00327C8,
	0xBF597FC7,
	0xC6E00BF3,
	0xD5A79147,
	0x06CA6351,
	0x14292967,
	0x27B70A85,
	0x2E1B2138,
	0x4D2C6DFC,
	0x53380D13,
	0x650A7354,
	0x766A0ABB,
	0x81C2C92E,
	0x92722C85,
	0xA2BFE8A1,
	0xA81A664B,
	0xC24B8B70,
	0xC76C51A3,
	0xD192E819,
	0xD6990624,
	0xF40E3585,
	0x106AA070,
	0x19A4C116,
	0x1E376C08,
	0x2748774C,
	0x34B0BCB5,
	0x391C0CB3,
	0x4ED8AA4A,
	0x5B9CCA4F,
	0x682E6FF3,
	0x748F82EE,
	0x78A5636F,
	0x84C87814,
	0x8CC70208,
	0x90BEFFFA,
	0xA4506CEB,
	0xBEF9A3F7,
	0xC67178F2,
}

local function add(...: number): number
	local total = 0
	for index = 1, select("#", ...) do
		total = (total + select(index, ...)) % WORD
	end
	return total
end

local function bytesFrom(source: any, offset: number?, length: number?): { number }
	local out = {}
	if type(source) == "string" then
		local start = if offset == nil then 0 else offset
		local count = if length == nil then #source - start else length
		for index = 0, count - 1 do
			out[#out + 1] = string.byte(source, start + index + 1)
		end
		return out
	end
	assert(typeof(source) == "buffer", "[Merveille/SHA256] expected string or buffer")
	local start = if offset == nil then 0 else offset
	local count = if length == nil then buffer.len(source) - start else length
	for index = 0, count - 1 do
		out[#out + 1] = buffer.readu8(source, start + index)
	end
	return out
end

local function writeWordBE(target: buffer, offset: number, value: number)
	buffer.writeu8(target, offset, bit32.band(bit32.rshift(value, 24), 0xFF))
	buffer.writeu8(target, offset + 1, bit32.band(bit32.rshift(value, 16), 0xFF))
	buffer.writeu8(target, offset + 2, bit32.band(bit32.rshift(value, 8), 0xFF))
	buffer.writeu8(target, offset + 3, bit32.band(value, 0xFF))
end

local function digestBytes(bytes: { number }): buffer
	local bitLength = #bytes * 8
	bytes[#bytes + 1] = 0x80
	while (#bytes % 64) ~= 56 do
		bytes[#bytes + 1] = 0
	end

	local high = math.floor(bitLength / WORD)
	local low = bitLength % WORD
	bytes[#bytes + 1] = bit32.band(bit32.rshift(high, 24), 0xFF)
	bytes[#bytes + 1] = bit32.band(bit32.rshift(high, 16), 0xFF)
	bytes[#bytes + 1] = bit32.band(bit32.rshift(high, 8), 0xFF)
	bytes[#bytes + 1] = bit32.band(high, 0xFF)
	bytes[#bytes + 1] = bit32.band(bit32.rshift(low, 24), 0xFF)
	bytes[#bytes + 1] = bit32.band(bit32.rshift(low, 16), 0xFF)
	bytes[#bytes + 1] = bit32.band(bit32.rshift(low, 8), 0xFF)
	bytes[#bytes + 1] = bit32.band(low, 0xFF)

	local h0 = 0x6A09E667
	local h1 = 0xBB67AE85
	local h2 = 0x3C6EF372
	local h3 = 0xA54FF53A
	local h4 = 0x510E527F
	local h5 = 0x9B05688C
	local h6 = 0x1F83D9AB
	local h7 = 0x5BE0CD19

	local w = table.create(64, 0)

	for chunk = 1, #bytes, 64 do
		for index = 0, 15 do
			local at = chunk + index * 4
			w[index + 1] = bit32.bor(
				bit32.lshift(bytes[at], 24),
				bit32.lshift(bytes[at + 1], 16),
				bit32.lshift(bytes[at + 2], 8),
				bytes[at + 3]
			)
		end

		for index = 17, 64 do
			local v15 = w[index - 15]
			local s0 = bit32.bxor(bit32.rrotate(v15, 7), bit32.rrotate(v15, 18), bit32.rshift(v15, 3))
			local v2 = w[index - 2]
			local s1 = bit32.bxor(bit32.rrotate(v2, 17), bit32.rrotate(v2, 19), bit32.rshift(v2, 10))
			w[index] = add(w[index - 16], s0, w[index - 7], s1)
		end

		local a = h0
		local b = h1
		local c = h2
		local d = h3
		local e = h4
		local f = h5
		local g = h6
		local h = h7

		for index = 1, 64 do
			local s1 = bit32.bxor(bit32.rrotate(e, 6), bit32.rrotate(e, 11), bit32.rrotate(e, 25))
			local ch = bit32.bxor(bit32.band(e, f), bit32.band(bit32.bnot(e), g))
			local temp1 = add(h, s1, ch, K[index], w[index])
			local s0 = bit32.bxor(bit32.rrotate(a, 2), bit32.rrotate(a, 13), bit32.rrotate(a, 22))
			local maj = bit32.bxor(bit32.band(a, b), bit32.band(a, c), bit32.band(b, c))
			local temp2 = add(s0, maj)

			h = g
			g = f
			f = e
			e = add(d, temp1)
			d = c
			c = b
			b = a
			a = add(temp1, temp2)
		end

		h0 = add(h0, a)
		h1 = add(h1, b)
		h2 = add(h2, c)
		h3 = add(h3, d)
		h4 = add(h4, e)
		h5 = add(h5, f)
		h6 = add(h6, g)
		h7 = add(h7, h)
	end

	local out = buffer.create(32)
	writeWordBE(out, 0, h0)
	writeWordBE(out, 4, h1)
	writeWordBE(out, 8, h2)
	writeWordBE(out, 12, h3)
	writeWordBE(out, 16, h4)
	writeWordBE(out, 20, h5)
	writeWordBE(out, 24, h6)
	writeWordBE(out, 28, h7)
	return out
end

function SHA256.compute(source: any, offset: number?, length: number?): buffer
	return digestBytes(bytesFrom(source, offset, length))
end

function SHA256.hex(source: any, offset: number?, length: number?): string
	local digest = SHA256.compute(source, offset, length)
	local out = table.create(64)
	for index = 0, 31 do
		out[index + 1] = string.format("%02x", buffer.readu8(digest, index))
	end
	return table.concat(out)
end

return table.freeze(SHA256)
