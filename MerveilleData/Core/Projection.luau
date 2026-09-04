--!strict

-->	["projection"]
-->	Client mirror schema projection.
-->	A projection owns only the miroir slice. It does not need the full wake,
-->	it does not need the full page body, and it does not need transient tables
-->	from the server just to read a small replicated view.
-->
-->	packet kinds:
-->	1 = keyframe
-->	2 = reliable raw delta
-->	3 = xor delta for unreliable cadence

local Text = require(script.Parent.Text)
local Xor = require(script.Parent.Xor)

local Projection = {}
Projection.__index = Projection

local SCALAR_READERS = {
	u8 = buffer.readu8,
	u16 = buffer.readu16,
	u32 = buffer.readu32,
	i8 = buffer.readi8,
	i16 = buffer.readi16,
	i32 = buffer.readi32,
	f32 = buffer.readf32,
}

local SCALAR_WRITERS = {
	u8 = buffer.writeu8,
	u16 = buffer.writeu16,
	u32 = buffer.writeu32,
	i8 = buffer.writei8,
	i16 = buffer.writei16,
	i32 = buffer.writei32,
	f32 = buffer.writef32,
}

local function copyBytes(target: buffer, targetOffset: number, source: buffer, sourceOffset: number, count: number)
	if count <= 0 then
		return
	end
	Xor.copy(target, targetOffset, source, sourceOffset, count)
end

local function cloneDescriptor(descriptor: any, offset: number)
	local projected = table.clone(descriptor)
	projected.offset = offset
	if descriptor.kind == "scalar" then
		local scalar = descriptor.scalar
		if scalar == "bool" then
			projected.read = function(source: buffer)
				return buffer.readu8(source, offset) ~= 0
			end
			projected.write = function(target: buffer, value: any)
				buffer.writeu8(target, offset, value and 1 or 0)
			end
		else
			local reader = SCALAR_READERS[scalar]
			local writer = SCALAR_WRITERS[scalar]
			projected.read = function(source: buffer)
				return reader(source, offset)
			end
			projected.write = function(target: buffer, value: any)
				writer(target, offset, value)
			end
		end
	elseif descriptor.kind == "text" then
		local maxBytes = descriptor.maxBytes
		projected.read = function(source: buffer)
			return Text.readFixed(source, offset, maxBytes)
		end
		projected.write = function(target: buffer, value: string)
			Text.writeFixed(target, offset, maxBytes, value)
		end
	end
	return projected
end

local function readScalarKind(source: buffer, scalar: string, offset: number)
	if scalar == "bool" then
		return buffer.readu8(source, offset) ~= 0
	end
	local reader = SCALAR_READERS[scalar]
	assert(reader ~= nil, `[Merveille/Projection] unsupported scalar kind '{scalar}'`)
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

local function readProjected(source: buffer, descriptor: any)
	local reader = descriptor.read
	if reader ~= nil then
		return reader(source)
	end
	if descriptor.kind == "bits" then
		return readBits(source, descriptor)
	elseif descriptor.kind == "vec" then
		return readVector(source, descriptor)
	elseif descriptor.kind == "blob" then
		return readBlob(source, descriptor)
	end
	error(`[Merveille/Projection] unsupported descriptor kind '{descriptor.kind}'`)
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

export type ProjectionObject = typeof(setmetatable(
	{} :: {
		Schema: any,
		Size: number,
		Revision: number,
		KeyframeRevision: number,
		Kind: string,
		Buffer: buffer,
		Entries: { any },
		ByPath: { [string]: any },
	},
	Projection
))

function Projection.new(schema: any): ProjectionObject
	assert(
		type(schema) == "table" and type(schema.MirrorEntries) == "table",
		"[Merveille/Projection] expected a compiled reliquary schema"
	)
	local entries = table.create(#schema.MirrorEntries)
	local byPath = {}
	for index, entry in ipairs(schema.MirrorEntries) do
		local projected = {
			path = entry.path,
			segments = entry.segments or string.split(entry.path, "."),
			descriptor = cloneDescriptor(entry.descriptor, entry.destOffset),
		}
		entries[index] = projected
		byPath[entry.path] = projected.descriptor
	end
	return setmetatable({
		Schema = schema,
		Size = schema.MirrorSize,
		Revision = 0,
		KeyframeRevision = 0,
		Kind = "Empty",
		Buffer = buffer.create(schema.MirrorSize),
		Entries = entries,
		ByPath = byPath,
	}, Projection)
end

function Projection:clear()
	self.Buffer = buffer.create(self.Size)
	self.Revision = 0
	self.KeyframeRevision = 0
	self.Kind = "Empty"
end

function Projection:apply(packet: buffer, length: number?): (boolean, string)
	local count = if length == nil then buffer.len(packet) else length
	if count < 5 then
		return false, "packet too small"
	end

	local kind = buffer.readu8(packet, 0)
	local revision = buffer.readu32(packet, 1)

	if kind == 1 then
		if count < 9 then
			return false, "keyframe header too small"
		end
		local size = buffer.readu32(packet, 5)
		if size ~= self.Size then
			return false, "keyframe size mismatch"
		end
		if count < 9 + size then
			return false, "keyframe payload truncated"
		end
		copyBytes(self.Buffer, 0, packet, 9, size)
		self.Revision = revision
		self.KeyframeRevision = revision
		self.Kind = "Keyframe"
		return true, "Keyframe"
	elseif kind == 2 or kind == 3 then
		if self.Kind == "Empty" then
			return false, "projection needs a keyframe first"
		end
		if count < 11 then
			return false, "delta header too small"
		end
		local baseRevision = buffer.readu32(packet, 5)
		if baseRevision ~= self.Revision then
			return false, "base revision mismatch"
		end
		local spanCount = buffer.readu16(packet, 9)
		local cursor = 11
		for _ = 1, spanCount do
			if cursor + 4 > count then
				return false, "delta spans truncated"
			end
			local offset = buffer.readu16(packet, cursor)
			local span = buffer.readu16(packet, cursor + 2)
			cursor += 4
			if offset + span > self.Size then
				return false, "delta span exceeds mirror size"
			end
			if cursor + span > count then
				return false, "delta payload truncated"
			end
			if kind == 2 then
				copyBytes(self.Buffer, offset, packet, cursor, span)
			else
				Xor.apply(self.Buffer, offset, packet, cursor, span)
			end
			cursor += span
		end
		self.Revision = revision
		self.Kind = if kind == 2 then "Delta" else "Xor"
		return true, self.Kind
	end

	return false, "unknown packet kind"
end

function Projection:read(path: string)
	local descriptor = self.ByPath[path]
	assert(descriptor ~= nil, `[Merveille/Projection] unknown projected path '{path}'`)
	return readProjected(self.Buffer, descriptor)
end

function Projection:project()
	local projected = {}
	for _, entry in ipairs(self.Entries) do
		writePath(projected, entry.segments, readProjected(self.Buffer, entry.descriptor))
	end
	return projected
end

function Projection:view()
	return self:project()
end

function Projection:describe()
	return {
		revision = self.Revision,
		keyframeRevision = self.KeyframeRevision,
		kind = self.Kind,
		paths = #self.Entries,
		bytes = self.Size,
		buffer = self.Buffer,
	}
end

return table.freeze({
	new = Projection.new,
})
