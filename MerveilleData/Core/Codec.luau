--!strict

local Codec = {}

local BUFFER_COPY = buffer.copy
local BUFFER_TO_STRING = buffer.tostring
local BUFFER_FROM_STRING = buffer.fromstring

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local CHAR_BY_VALUE: {[number]: string} = {}
local VALUE_BY_CHAR: {[number]: number} = {}

for index = 1, #ALPHABET do
	local byte = string.byte(ALPHABET, index)
	CHAR_BY_VALUE[index - 1] = string.char(byte)
	VALUE_BY_CHAR[byte] = index - 1
end

local function copyPrefix(target: buffer, source: buffer, length: number)
	if BUFFER_COPY ~= nil then
		BUFFER_COPY(target, 0, source, 0, length)
		return
	end
	for index = 0, length - 1 do
		buffer.writeu8(target, index, buffer.readu8(source, index))
	end
end

local function encodeBase64(source: buffer, length: number): string
	local out = table.create(math.ceil(length / 3) * 4)
	local outIndex = 1
	local read = 0

	while read + 2 < length do
		local a = buffer.readu8(source, read)
		local b = buffer.readu8(source, read + 1)
		local c = buffer.readu8(source, read + 2)
		local packed = bit32.bor(bit32.lshift(a, 16), bit32.lshift(b, 8), c)

		out[outIndex] = CHAR_BY_VALUE[bit32.band(bit32.rshift(packed, 18), 0x3F)]
		out[outIndex + 1] = CHAR_BY_VALUE[bit32.band(bit32.rshift(packed, 12), 0x3F)]
		out[outIndex + 2] = CHAR_BY_VALUE[bit32.band(bit32.rshift(packed, 6), 0x3F)]
		out[outIndex + 3] = CHAR_BY_VALUE[bit32.band(packed, 0x3F)]

		read += 3
		outIndex += 4
	end

	local remainder = length - read
	if remainder == 1 then
		local a = buffer.readu8(source, read)
		local packed = bit32.lshift(a, 16)
		out[outIndex] = CHAR_BY_VALUE[bit32.band(bit32.rshift(packed, 18), 0x3F)]
		out[outIndex + 1] = CHAR_BY_VALUE[bit32.band(bit32.rshift(packed, 12), 0x3F)]
		out[outIndex + 2] = "="
		out[outIndex + 3] = "="
	elseif remainder == 2 then
		local a = buffer.readu8(source, read)
		local b = buffer.readu8(source, read + 1)
		local packed = bit32.bor(bit32.lshift(a, 16), bit32.lshift(b, 8))
		out[outIndex] = CHAR_BY_VALUE[bit32.band(bit32.rshift(packed, 18), 0x3F)]
		out[outIndex + 1] = CHAR_BY_VALUE[bit32.band(bit32.rshift(packed, 12), 0x3F)]
		out[outIndex + 2] = CHAR_BY_VALUE[bit32.band(bit32.rshift(packed, 6), 0x3F)]
		out[outIndex + 3] = "="
	end

	return table.concat(out)
end

local function decodeBase64(encoded: string, exactLength: number?): buffer
	local padding = 0
	if encoded:sub(-2) == "==" then
		padding = 2
	elseif encoded:sub(-1) == "=" then
		padding = 1
	end

	local outputLength = exactLength or ((#encoded // 4) * 3 - padding)
	local out = buffer.create(outputLength)
	local write = 0
	local index = 1

	while index <= #encoded do
		local c1 = string.byte(encoded, index)
		local c2 = string.byte(encoded, index + 1)
		local c3 = string.byte(encoded, index + 2)
		local c4 = string.byte(encoded, index + 3)

		local v1 = VALUE_BY_CHAR[c1] or 0
		local v2 = VALUE_BY_CHAR[c2] or 0
		local v3 = if c3 == string.byte("=") then 0 else (VALUE_BY_CHAR[c3] or 0)
		local v4 = if c4 == string.byte("=") then 0 else (VALUE_BY_CHAR[c4] or 0)

		local packed = bit32.bor(
			bit32.lshift(v1, 18),
			bit32.lshift(v2, 12),
			bit32.lshift(v3, 6),
			v4
		)

		if write < outputLength then
			buffer.writeu8(out, write, bit32.band(bit32.rshift(packed, 16), 0xFF))
			write += 1
		end
		if c3 ~= string.byte("=") and write < outputLength then
			buffer.writeu8(out, write, bit32.band(bit32.rshift(packed, 8), 0xFF))
			write += 1
		end
		if c4 ~= string.byte("=") and write < outputLength then
			buffer.writeu8(out, write, bit32.band(packed, 0xFF))
			write += 1
		end

		index += 4
	end

	return out
end

function Codec.encode(source: buffer, length: number): string
	if BUFFER_TO_STRING ~= nil then
		if length == buffer.len(source) then
			return BUFFER_TO_STRING(source)
		end
		local slice = buffer.create(length)
		copyPrefix(slice, source, length)
		return BUFFER_TO_STRING(slice)
	end

	return encodeBase64(source, length)
end

function Codec.decode(encoded: any, exactLength: number?): buffer
	if typeof(encoded) == "buffer" then
		if exactLength == nil or buffer.len(encoded) == exactLength then
			return encoded
		end
		local resized = buffer.create(exactLength)
		copyPrefix(resized, encoded, math.min(exactLength, buffer.len(encoded)))
		return resized
	end

	assert(type(encoded) == "string", "[Merveille/Codec] expected string or buffer payload")

	if BUFFER_FROM_STRING ~= nil and exactLength ~= nil and #encoded == exactLength then
		return BUFFER_FROM_STRING(encoded)
	end

	return decodeBase64(encoded, exactLength)
end

return table.freeze(Codec)
