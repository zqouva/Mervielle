--!strict

local Hash = require(script.Parent.Hash)
local Text = require(script.Parent.Text)

local Compiler = {}

local PAGE_SIZE = 0x1000
local HEADER_SIZE = 0x0100
local BUFFER_COPY = buffer.copy
local BUFFER_FILL = buffer.fill

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

local function sortedKeys(map: { [string]: any }): { string }
	local keys = {}
	for key in map do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	return keys
end

local function copyBytes(target: buffer, targetOffset: number, source: buffer, sourceOffset: number, count: number)
	if count <= 0 then
		return
	end
	if BUFFER_COPY ~= nil then
		BUFFER_COPY(target, targetOffset, source, sourceOffset, count)
		return
	end
	for index = 0, count - 1 do
		buffer.writeu8(target, targetOffset + index, buffer.readu8(source, sourceOffset + index))
	end
end

local function clearBytes(target: buffer, offset: number, count: number)
	if count <= 0 then
		return
	end
	if BUFFER_FILL ~= nil then
		BUFFER_FILL(target, offset, 0, count)
		return
	end
	for index = 0, count - 1 do
		buffer.writeu8(target, offset + index, 0)
	end
end

local function alignTo(offset: number, alignment: number): number
	if alignment <= 1 then
		return offset
	end
	local remainder = offset % alignment
	if remainder == 0 then
		return offset
	end
	return offset + (alignment - remainder)
end

local function scalarWidth(kind: string): number
	if kind == "u8" or kind == "i8" or kind == "bool" then
		return 1
	elseif kind == "u16" or kind == "i16" then
		return 2
	elseif kind == "u32" or kind == "i32" or kind == "f32" then
		return 4
	end
	error(`[Merveille/Compiler] unsupported scalar kind {kind}`)
end

local function scalarAlignment(kind: string): number
	local width = scalarWidth(kind)
	return if width >= 4 then 4 else width
end

local function scalarReadAt(kind: string, source: buffer, offset: number)
	if kind == "bool" then
		return buffer.readu8(source, offset) ~= 0
	end
	local reader = SCALAR_READERS[kind]
	assert(reader ~= nil, `[Merveille/Compiler] unsupported scalar reader '{kind}'`)
	return reader(source, offset)
end

local function scalarWriteAt(kind: string, target: buffer, offset: number, value: any)
	if kind == "bool" then
		buffer.writeu8(target, offset, value and 1 or 0)
		return
	end
	local writer = SCALAR_WRITERS[kind]
	assert(writer ~= nil, `[Merveille/Compiler] unsupported scalar writer '{kind}'`)
	writer(target, offset, value)
end

local function scalarReader(kind: string, offset: number)
	return function(source: buffer)
		return scalarReadAt(kind, source, offset)
	end
end

local function scalarWriter(kind: string, offset: number)
	return function(target: buffer, value: any)
		scalarWriteAt(kind, target, offset, value)
	end
end

local function bitsReader(offset: number, count: number, map: { [string]: number })
	return function(source: buffer)
		if next(map) ~= nil then
			local flags = {}
			for name, index in map do
				local byteOffset = offset + math.floor(index / 8)
				local mask = bit32.lshift(1, index % 8)
				flags[name] = bit32.band(buffer.readu8(source, byteOffset), mask) ~= 0
			end
			return flags
		end
		local flags = table.create(count)
		for index = 0, count - 1 do
			local byteOffset = offset + math.floor(index / 8)
			local mask = bit32.lshift(1, index % 8)
			flags[index + 1] = bit32.band(buffer.readu8(source, byteOffset), mask) ~= 0
		end
		return flags
	end
end

local function bitsWriter(offset: number, count: number, map: { [string]: number })
	local byteCount = math.ceil(count / 8)
	return function(target: buffer, value: any)
		clearBytes(target, offset, byteCount)
		if type(value) ~= "table" then
			return
		end
		for key, enabled in value do
			local position = if type(key) == "number" then key - 1 else map[key]
			if position ~= nil and enabled then
				local byteOffset = offset + math.floor(position / 8)
				local mask = bit32.lshift(1, position % 8)
				buffer.writeu8(target, byteOffset, bit32.bor(buffer.readu8(target, byteOffset), mask))
			end
		end
	end
end

local function blobReader(offset: number, bytes: number)
	return function(source: buffer)
		local out = buffer.create(bytes)
		copyBytes(out, 0, source, offset, bytes)
		return out
	end
end

local function blobWriter(offset: number, bytes: number)
	return function(target: buffer, value: any)
		clearBytes(target, offset, bytes)
		if value == nil then
			return
		end
		if type(value) == "string" then
			local count = math.min(bytes, #value)
			for index = 0, count - 1 do
				buffer.writeu8(target, offset + index, string.byte(value, index + 1))
			end
			return
		end
		assert(typeof(value) == "buffer", `[Merveille/Compiler] blob writer expected string or buffer`)
		copyBytes(target, offset, value, 0, math.min(bytes, buffer.len(value)))
	end
end

local function vecReader(offset: number, elementKind: string, elementWidth: number)
	return function(source: buffer)
		local count = buffer.readu16(source, offset)
		local out = table.create(count)
		local lane = offset + 4
		for index = 1, count do
			out[index] = scalarReadAt(elementKind, source, lane + (index - 1) * elementWidth)
		end
		return out
	end
end

local function vecWriter(offset: number, elementKind: string, elementWidth: number, capacity: number)
	return function(target: buffer, value: any)
		clearBytes(target, offset + 4, elementWidth * capacity)
		local count = 0
		if type(value) == "table" then
			for index, item in ipairs(value) do
				if index > capacity then
					break
				end
				count += 1
				scalarWriteAt(elementKind, target, offset + 4 + (index - 1) * elementWidth, item)
			end
		end
		buffer.writeu16(target, offset, count)
		buffer.writeu16(target, offset + 2, capacity)
	end
end

local function compileField(
	name: string,
	definition: any,
	path: string,
	offset: number,
	descriptors: { any },
	byPath: { [string]: any },
	nextId: number
): (any, number, number)
	assert(
		type(definition) == "table" and type(definition.__m_kind) == "string",
		`[Merveille/Compiler] field '{path}' is not a valid Merveille descriptor`
	)

	local kind = definition.__m_kind

	if kind == "scalar" then
		local scalarKind = definition.scalar :: string
		offset = alignTo(offset, scalarAlignment(scalarKind))
		local width = scalarWidth(scalarKind)
		local descriptor = {
			id = nextId,
			name = name,
			path = path,
			kind = kind,
			scalar = scalarKind,
			offset = offset,
			size = width,
			align = scalarAlignment(scalarKind),
			read = scalarReader(scalarKind, offset),
			write = scalarWriter(scalarKind, offset),
		}
		descriptors[#descriptors + 1] = descriptor
		byPath[path] = descriptor
		return descriptor, offset + width, nextId + 1
	elseif kind == "text" then
		local maxBytes = definition.maxBytes :: number
		offset = alignTo(offset, 2)
		local descriptor = {
			id = nextId,
			name = name,
			path = path,
			kind = kind,
			maxBytes = maxBytes,
			offset = offset,
			size = 2 + maxBytes,
			align = 2,
			read = function(source: buffer)
				return Text.readFixed(source, offset, maxBytes)
			end,
			write = function(target: buffer, value: string)
				Text.writeFixed(target, offset, maxBytes, value)
			end,
		}
		descriptors[#descriptors + 1] = descriptor
		byPath[path] = descriptor
		return descriptor, offset + descriptor.size, nextId + 1
	elseif kind == "bits" then
		local count = definition.count :: number
		local descriptor = {
			id = nextId,
			name = name,
			path = path,
			kind = kind,
			count = count,
			map = definition.map,
			offset = offset,
			size = math.ceil(count / 8),
			align = 1,
			read = bitsReader(offset, count, definition.map),
			write = bitsWriter(offset, count, definition.map),
		}
		descriptors[#descriptors + 1] = descriptor
		byPath[path] = descriptor
		return descriptor, offset + descriptor.size, nextId + 1
	elseif kind == "blob" then
		local bytes = definition.bytes :: number
		local descriptor = {
			id = nextId,
			name = name,
			path = path,
			kind = kind,
			bytes = bytes,
			offset = offset,
			size = bytes,
			align = 1,
			read = blobReader(offset, bytes),
			write = blobWriter(offset, bytes),
		}
		descriptors[#descriptors + 1] = descriptor
		byPath[path] = descriptor
		return descriptor, offset + bytes, nextId + 1
	elseif kind == "vec" then
		local element = definition.element
		assert(
			element.__m_kind == "scalar",
			`[Merveille/Compiler] vec field '{path}' currently supports scalar element types only`
		)
		local elementKind = element.scalar :: string
		local elementWidth = scalarWidth(elementKind)
		offset = alignTo(offset, math.max(2, scalarAlignment(elementKind)))
		local descriptor = {
			id = nextId,
			name = name,
			path = path,
			kind = kind,
			element = elementKind,
			elementWidth = elementWidth,
			capacity = definition.capacity,
			offset = offset,
			size = 4 + elementWidth * definition.capacity,
			align = math.max(2, scalarAlignment(elementKind)),
			read = vecReader(offset, elementKind, elementWidth),
			write = vecWriter(offset, elementKind, elementWidth, definition.capacity),
		}
		descriptors[#descriptors + 1] = descriptor
		byPath[path] = descriptor
		return descriptor, offset + descriptor.size, nextId + 1
	elseif kind == "group" then
		local start = offset
		local childrenArray = {}
		local childrenMap = {}
		for _, childName in sortedKeys(definition.fields) do
			local childPath = `{path}.{childName}`
			local childDescriptor
			childDescriptor, offset, nextId =
				compileField(childName, definition.fields[childName], childPath, offset, descriptors, byPath, nextId)
			childrenArray[#childrenArray + 1] = childDescriptor
			childrenMap[childName] = childDescriptor
		end
		local descriptor = {
			id = nextId,
			name = name,
			path = path,
			kind = kind,
			offset = start,
			size = offset - start,
			fields = childrenArray,
			byName = childrenMap,
			align = 1,
		}
		byPath[path] = descriptor
		return descriptor, offset, nextId + 1
	end

	error(`[Merveille/Compiler] unsupported field kind '{kind}' for '{path}'`)
end

function Compiler.compile(definition: { [string]: any })
	assert(type(definition) == "table", "[Merveille/Compiler] profile definition must be a table")
	assert(type(definition.id) == "string" and definition.id ~= "", "[Merveille/Compiler] profile needs an id")
	assert(
		type(definition.pages) == "number" and definition.pages % 1 == 0 and definition.pages > 0,
		"[Merveille/Compiler] profile needs a positive integer page count"
	)
	local root = definition.traits or definition.sigils or definition.fields
	assert(type(root) == "table", "[Merveille/Compiler] reliquary needs a traits table")

	local byPath = {}
	local allDescriptors = {}
	local rootByName = {}
	local rootFields = {}
	local readers = {}
	local writers = {}
	local offset = HEADER_SIZE
	local nextId = 1

	for _, fieldName in sortedKeys(root) do
		local descriptor
		descriptor, offset, nextId =
			compileField(fieldName, root[fieldName], fieldName, offset, allDescriptors, byPath, nextId)
		rootFields[#rootFields + 1] = descriptor
		rootByName[fieldName] = descriptor
		if descriptor.kind ~= "group" then
			readers[fieldName] = descriptor.read
			writers[fieldName] = descriptor.write
		end
	end

	for path, descriptor in byPath do
		if descriptor.kind ~= "group" then
			readers[path] = descriptor.read
			writers[path] = descriptor.write
		end
	end

	local pageBytes = definition.pages * PAGE_SIZE
	assert(
		offset <= pageBytes,
		`[Merveille/Compiler] schema '{definition.id}' uses {offset} bytes but only {pageBytes} are available`
	)

	local descriptorById = {}
	local payloadBytes = 0
	for index = 1, #allDescriptors do
		local descriptor = allDescriptors[index]
		descriptorById[descriptor.id] = descriptor
		payloadBytes += descriptor.size
	end

	local mirrorEntries = {}
	local mirrorByDescriptorId = {}
	local mirrorPageBuckets = table.create(definition.pages)
	for page = 1, definition.pages do
		mirrorPageBuckets[page] = {}
	end
	local mirrorOffset = 0
	local mirrorList = definition.miroir or definition.mirror or {}
	for _, path in ipairs(mirrorList) do
		local descriptor = byPath[path]
		assert(descriptor ~= nil, `[Merveille/Compiler] mirror path '{path}' does not exist`)
		assert(descriptor.kind ~= "group", `[Merveille/Compiler] mirror path '{path}' cannot target a group directly`)
		local entry = {
			id = #mirrorEntries + 1,
			path = path,
			segments = string.split(path, "."),
			sourceOffset = descriptor.offset,
			size = descriptor.size,
			destOffset = mirrorOffset,
			descriptor = descriptor,
		}
		mirrorEntries[#mirrorEntries + 1] = entry
		local descriptorEntries = mirrorByDescriptorId[descriptor.id]
		if descriptorEntries == nil then
			descriptorEntries = {}
			mirrorByDescriptorId[descriptor.id] = descriptorEntries
		end
		descriptorEntries[#descriptorEntries + 1] = entry
		local firstPage = math.floor(entry.sourceOffset / PAGE_SIZE) + 1
		local lastPage = math.floor((entry.sourceOffset + math.max(entry.size - 1, 0)) / PAGE_SIZE) + 1
		for page = firstPage, lastPage do
			local bucket = mirrorPageBuckets[page]
			bucket[#bucket + 1] = entry
		end
		mirrorOffset += descriptor.size
	end

	local schemaHash =
		Hash.fnv1a32(definition.id .. ":" .. tostring(definition.version or 1) .. ":" .. tostring(offset))
	local alignmentWaste = math.max(0, offset - HEADER_SIZE - payloadBytes)
	local slackBytes = math.max(0, pageBytes - offset)

	local schema = {
		Id = definition.id,
		Version = definition.version or 1,
		Pages = definition.pages,
		PageBytes = pageBytes,
		HeaderBytes = HEADER_SIZE,
		LayoutEnd = offset,
		Hash = schemaHash,
		FieldCount = nextId - 1,
		RootFields = rootFields,
		RootByName = rootByName,
		ByPath = byPath,
		Descriptors = allDescriptors,
		DescriptorById = descriptorById,
		ReadByPath = readers,
		WriteByPath = writers,
		MirrorEntries = mirrorEntries,
		MirrorByDescriptorId = mirrorByDescriptorId,
		MirrorPageBuckets = mirrorPageBuckets,
		MirrorSize = mirrorOffset,
		PayloadBytes = payloadBytes,
		AlignmentWaste = alignmentWaste,
		SlackBytes = slackBytes,
		Defaults = definition.defaults or definition.defauts or {},
		Migrations = definition.migrations or {},
	}

	return table.freeze(schema)
end

return table.freeze(Compiler)
