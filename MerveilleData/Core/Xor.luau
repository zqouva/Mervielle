--!strict

-->	["xor"]
-->	Binary xor helpers for mirror diffing and patch application.
-->	The point is simple: keep diffs buffer-native so the runtime does not
-->	need to build transient dictionary payloads just to move a handful of bytes.

local Xor = {}

local function copyBytes(target: buffer, targetOffset: number, source: buffer, sourceOffset: number, count: number)
	if count <= 0 then
		return
	end
	if buffer.copy ~= nil then
		buffer.copy(target, targetOffset, source, sourceOffset, count)
		return
	end
	for index = 0, count - 1 do
		buffer.writeu8(target, targetOffset + index, buffer.readu8(source, sourceOffset + index))
	end
end

function Xor.span(
	target: buffer,
	targetOffset: number,
	left: buffer,
	leftOffset: number,
	right: buffer,
	rightOffset: number,
	count: number
)
	for index = 0, count - 1 do
		local a = buffer.readu8(left, leftOffset + index)
		local b = buffer.readu8(right, rightOffset + index)
		buffer.writeu8(target, targetOffset + index, bit32.band(bit32.bxor(a, b), 0xFF))
	end
end

function Xor.apply(target: buffer, targetOffset: number, patch: buffer, patchOffset: number, count: number)
	for index = 0, count - 1 do
		local value = buffer.readu8(target, targetOffset + index)
		local delta = buffer.readu8(patch, patchOffset + index)
		buffer.writeu8(target, targetOffset + index, bit32.band(bit32.bxor(value, delta), 0xFF))
	end
end

function Xor.copy(target: buffer, targetOffset: number, source: buffer, sourceOffset: number, count: number)
	copyBytes(target, targetOffset, source, sourceOffset, count)
end

function Xor.changed(left: buffer, leftOffset: number, right: buffer, rightOffset: number, count: number): boolean
	for index = 0, count - 1 do
		if buffer.readu8(left, leftOffset + index) ~= buffer.readu8(right, rightOffset + index) then
			return true
		end
	end
	return false
end

function Xor.measure(source: buffer, sourceOffset: number, count: number): number
	local changed = 0
	for index = 0, count - 1 do
		if buffer.readu8(source, sourceOffset + index) ~= 0 then
			changed += 1
		end
	end
	return changed
end

return table.freeze(Xor)
