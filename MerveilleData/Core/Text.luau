--!strict

local Text = {}

local BUFFER_FILL = buffer.fill
local BUFFER_WRITE_STRING = buffer.writestring
local BUFFER_READ_STRING = buffer.readstring

local function clearRange(target: buffer, offset: number, length: number)
	if length <= 0 then
		return
	end
	if BUFFER_FILL ~= nil then
		BUFFER_FILL(target, offset, 0, length)
		return
	end
	for index = 0, length - 1 do
		buffer.writeu8(target, offset + index, 0)
	end
end

function Text.writeFixed(target: buffer, offset: number, maxBytes: number, value: string)
	assert(type(value) == "string", "[Merveille/Text] value must be a string")
	local length = #value
	assert(length <= maxBytes, `[Merveille/Text] string of {length} bytes exceeds text[{maxBytes}]`)

	buffer.writeu16(target, offset, length)
	clearRange(target, offset + 2, maxBytes)
	if length <= 0 then
		return
	end

	if BUFFER_WRITE_STRING ~= nil then
		BUFFER_WRITE_STRING(target, offset + 2, value)
		return
	end

	for index = 1, length do
		buffer.writeu8(target, offset + 2 + index - 1, string.byte(value, index))
	end
end

function Text.readFixed(source: buffer, offset: number, maxBytes: number): string
	local length = math.min(buffer.readu16(source, offset), maxBytes)
	if length <= 0 then
		return ""
	end

	if BUFFER_READ_STRING ~= nil then
		return BUFFER_READ_STRING(source, offset + 2, length)
	end

	local chars = table.create(length)
	for index = 1, length do
		chars[index] = string.char(buffer.readu8(source, offset + 2 + index - 1))
	end
	return table.concat(chars)
end

return table.freeze(Text)
