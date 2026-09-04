--!strict

-->	["view"]
-->	Schema-shaped read views over the full wake buffer.
-->	Phase 4 asked for views. This module keeps them compiled and explicit.
-->	It can read from a live wake, a read-only wake, or a raw buffer.

local Text = require(script.Parent.Text)
local Xor = require(script.Parent.Xor)

local View = {}
View.__index = View

local SCALAR_READERS = {
	u8 = buffer.readu8,
	u16 = buffer.readu16,
	u32 = buffer.readu32,
	i8 = buffer.readi8,
	i16 = buffer.readi16,
	i32 = buffer.readi32,
	f32 = buffer.readf32,
}

local function copyBytes(target: buffer, targetOffset: number, source: buffer, sourceOffset: number, count: number)
	if count <= 0 then
		return
	end
	Xor.copy(target, targetOffset, source, sourceOffset, count)
end

local function sourceBuffer(subject: any): buffer
	if typeof(subject) == "buffer" then
		return subject
	end
	assert(type(subject) == "table" and subject._buffer ~= nil, "[Merveille/View] expected a wake or buffer subject")
	return subject._buffer
end

local function readScalarKind(source: buffer, scalar: string, offset: number)
	if scalar == "bool" then
		return buffer.readu8(source, offset) ~= 0
	end
	local reader = SCALAR_READERS[scalar]
	assert(reader ~= nil, `[Merveille/View] unsupported scalar kind '{scalar}'`)
	return reader(source, offset)
end

local function readBits(source: buffer, descriptor: any)
	local named = descriptor.map
	if named ~= nil and next(named) ~= nil then
		local flags = {}
		for name, index in named do
			local byteOffset = descriptor.offset + math.floor(index / 8)
			local mask = bit32.lshift(1, index % 8)
			flags[name] = bit32.band(buffer.readu8(source, byteOffset), mask) ~= 0
		end
		return flags
	end
	local flags = table.create(descriptor.count)
	for index = 0, descriptor.count - 1 do
		local byteOffset = descriptor.offset + math.floor(index / 8)
		local mask = bit32.lshift(1, index % 8)
		flags[index + 1] = bit32.band(buffer.readu8(source, byteOffset), mask) ~= 0
	end
	return flags
end

local function readVector(source: buffer, descriptor: any)
	local count = buffer.readu16(source, descriptor.offset)
	local values = table.create(count)
	local lane = descriptor.offset + 4
	for index = 1, count do
		values[index] = readScalarKind(source, descriptor.element, lane + (index - 1) * descriptor.elementWidth)
	end
	return values
end

local function readBlob(source: buffer, descriptor: any)
	local lane = buffer.create(descriptor.size)
	copyBytes(lane, 0, source, descriptor.offset, descriptor.size)
	return lane
end

local function readDescriptor(source: buffer, descriptor: any)
	if descriptor.read ~= nil then
		return descriptor.read(source)
	elseif descriptor.kind == "bits" then
		return readBits(source, descriptor)
	elseif descriptor.kind == "vec" then
		return readVector(source, descriptor)
	elseif descriptor.kind == "blob" then
		return readBlob(source, descriptor)
	end
	error(`[Merveille/View] unsupported descriptor kind '{descriptor.kind}'`)
end

local function writePath(target: { [any]: any }, segments: { string }, value: any)
	local cursor = target
	for index = 1, #segments - 1 do
		local segment = segments[index]
		local nextCursor = cursor[segment]
		if nextCursor == nil then
			nextCursor = {}
			cursor[segment] = nextCursor
		end
		cursor = nextCursor
	end
	cursor[segments[#segments]] = value
end

function View.new(schema: any, paths: { string }?)
	assert(
		type(schema) == "table" and type(schema.ByPath) == "table",
		"[Merveille/View] expected a compiled reliquary schema"
	)
	local selected = table.create(if paths == nil then #schema.Descriptors else #paths)
	if paths == nil then
		for _, descriptor in ipairs(schema.Descriptors) do
			if descriptor.kind ~= "group" then
				selected[#selected + 1] = {
					path = descriptor.path,
					segments = string.split(descriptor.path, "."),
					descriptor = descriptor,
				}
			end
		end
	else
		for _, path in ipairs(paths) do
			local descriptor = schema.ByPath[path]
			assert(descriptor ~= nil, `[Merveille/View] unknown path '{path}'`)
			assert(descriptor.kind ~= "group", `[Merveille/View] path '{path}' cannot point at a group directly`)
			selected[#selected + 1] = {
				path = path,
				segments = string.split(path, "."),
				descriptor = descriptor,
			}
		end
	end
	return setmetatable({
		Schema = schema,
		Entries = selected,
	}, View)
end

function View:read(subject: any, path: string)
	local descriptor = self.Schema.ByPath[path]
	assert(descriptor ~= nil, `[Merveille/View] unknown path '{path}'`)
	assert(descriptor.kind ~= "group", `[Merveille/View] path '{path}' cannot point at a group directly`)
	return readDescriptor(sourceBuffer(subject), descriptor)
end

function View:project(subject: any)
	local source = sourceBuffer(subject)
	local projected = {}
	for _, entry in ipairs(self.Entries) do
		writePath(projected, entry.segments, readDescriptor(source, entry.descriptor))
	end
	return projected
end

function View:describe()
	return {
		paths = #self.Entries,
		schema = self.Schema.Id,
		version = self.Schema.Version,
	}
end

return table.freeze({
	new = View.new,
})
