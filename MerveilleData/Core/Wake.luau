--!strict

local Text = require(script.Parent.Text)
local CRC32 = require(script.Parent.CRC32)
local Xor = require(script.Parent.Xor)
local Result = require(script.Parent.Result)

local Wake = {}

local PAGE_SIZE = 0x1000
local FORMAT_VERSION = 1
local MAGIC = 0x4D52564C

local OFF_MAGIC = 0x0000
local OFF_FORMAT_VERSION = 0x0004
local OFF_SCHEMA_VERSION = 0x0006
local OFF_SCHEMA_HASH = 0x0008
local OFF_PAGE_COUNT = 0x000C
local OFF_FLAGS = 0x000E
local OFF_REVISION = 0x0010
local OFF_COMMIT = 0x0014
local OFF_LOCK_EPOCH = 0x0018
local OFF_OPEN_UNIX = 0x001C
local OFF_LAST_SAVE_UNIX = 0x0020
local OFF_BODY_BYTES = 0x0024
local OFF_BODY_CRC32 = 0x0028
local OFF_OWNER_PLACE = 0x002C
local OFF_OWNER_JOB = 0x0030
local OFF_SCHEMA_ID = 0x0072
local OFF_MIRROR_REVISION = 0x0094
local OFF_SEAL_VERSION = 0x0098
local OFF_SEAL_NONCE = 0x009C
local OFF_SEAL_MAC = 0x00AC
local HEADER_SIZE = 0x0100

local HEADER_OWNER_JOB_MAX = 64
local HEADER_SCHEMA_ID_MAX = 32
local FLAG_ACTIVE = 0x0001
local FLAG_SEALED = 0x0002

local BUFFER_COPY = buffer.copy
local BUFFER_FILL = buffer.fill

local WAKE_METHODS = {}
local GROUP_METHODS = {}
local VECTOR_METHODS = {}
local BITS_METHODS = {}

local WakeMT = {}
local GroupMT = {}
local VecMT = {}
local BitsMT = {}

local function fillBytes(target: buffer, offset: number, count: number, value: number)
	if count <= 0 then
		return
	end
	if BUFFER_FILL ~= nil then
		BUFFER_FILL(target, offset, value, count)
		return
	end
	for index = 0, count - 1 do
		buffer.writeu8(target, offset + index, value)
	end
end

local function clearBytes(target: buffer)
	fillBytes(target, 0, buffer.len(target), 0)
end

local function setBit(bits: buffer, zeroBasedIndex: number)
	local byteIndex = math.floor(zeroBasedIndex / 8)
	local bitOffset = zeroBasedIndex % 8
	local current = buffer.readu8(bits, byteIndex)
	buffer.writeu8(bits, byteIndex, bit32.bor(current, bit32.lshift(1, bitOffset)))
end

local function readBit(bits: buffer, zeroBasedIndex: number): boolean
	local byteIndex = math.floor(zeroBasedIndex / 8)
	local bitOffset = zeroBasedIndex % 8
	local current = buffer.readu8(bits, byteIndex)
	return bit32.band(current, bit32.lshift(1, bitOffset)) ~= 0
end

local function copyBytes(target: buffer, targetOffset: number, source: buffer, sourceOffset: number, length: number)
	if length <= 0 then
		return
	end
	if BUFFER_COPY ~= nil then
		BUFFER_COPY(target, targetOffset, source, sourceOffset, length)
		return
	end
	for index = 0, length - 1 do
		buffer.writeu8(target, targetOffset + index, buffer.readu8(source, sourceOffset + index))
	end
end

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

local SCALAR_WIDTHS = {
	u8 = 1,
	u16 = 2,
	u32 = 4,
	i8 = 1,
	i16 = 2,
	i32 = 4,
	f32 = 4,
}

local function readScalar(source: buffer, kind: string, offset: number): any
	if kind == "bool" then
		return buffer.readu8(source, offset) ~= 0
	end
	local reader = SCALAR_READERS[kind]
	if reader ~= nil then
		return reader(source, offset)
	end
	error(`[Merveille/Wake] unsupported scalar read kind '{kind}'`)
end

local function writeScalar(target: buffer, kind: string, offset: number, value: any)
	if kind == "bool" then
		buffer.writeu8(target, offset, value and 1 or 0)
		return
	end
	local writer = SCALAR_WRITERS[kind]
	if writer ~= nil then
		writer(target, offset, value)
		return
	end
	error(`[Merveille/Wake] unsupported scalar write kind '{kind}'`)
end

local function touchDescriptor(wake: any, descriptor: any)
	setBit(wake._fieldDirty, descriptor.id - 1)
	wake._dirty = true
end

local function markDirtyRange(wake: any, startOffset: number, length: number)
	if length <= 0 then
		return
	end

	local firstPage = math.floor(startOffset / PAGE_SIZE)
	local lastPage = math.floor((startOffset + length - 1) / PAGE_SIZE)
	for page = firstPage, lastPage do
		setBit(wake._pageDirty, page)
	end

	local spanCount = wake._spanCount
	if spanCount > 0 then
		local lastStart = wake._spanOffsets[spanCount]
		local lastLength = wake._spanLengths[spanCount]
		local lastEnd = lastStart + lastLength
		if startOffset <= lastEnd then
			local mergedEnd = math.max(lastEnd, startOffset + length)
			wake._spanLengths[spanCount] = mergedEnd - lastStart
			perfPeaks(wake)
			return
		end
	end

	if spanCount < wake._spanCapacity then
		spanCount += 1
		wake._spanOffsets[spanCount] = startOffset
		wake._spanLengths[spanCount] = length
		wake._spanCount = spanCount
	else
		wake._spanOffsets[1] = math.min(wake._spanOffsets[1], startOffset)
		local currentEnd = wake._spanOffsets[spanCount] + wake._spanLengths[spanCount]
		wake._spanLengths[1] = math.max(currentEnd, startOffset + length) - wake._spanOffsets[1]
		wake._spanCount = 1
	end
end

local function bumpRevision(wake: any)
	wake._revision += 1
end

local function perfAdd(wake: any, key: string, amount: number)
	local perf = wake._perf
	if perf ~= nil then
		perf[key] += amount
	end
end

local function perfPacket(wake: any, field: string, bytes: number)
	local perf = wake._perf
	if perf ~= nil then
		perf[field] += 1
		perf.PacketBytes += bytes
	end
end

local function perfPeaks(wake: any)
	local perf = wake._perf
	if perf ~= nil then
		if wake._spanCount > perf.DirtySpanPeak then
			perf.DirtySpanPeak = wake._spanCount
		end
		if wake._mirrorSpanCount > perf.MirrorSpanPeak then
			perf.MirrorSpanPeak = wake._mirrorSpanCount
		end
	end
end

local function queueMirrorSpan(wake: any, startOffset: number, length: number)
	if length <= 0 then
		return
	end

	local spanCount = wake._mirrorSpanCount
	if spanCount > 0 then
		local lastStart = wake._mirrorSpanOffsets[spanCount]
		local lastLength = wake._mirrorSpanLengths[spanCount]
		local lastEnd = lastStart + lastLength
		if startOffset <= lastEnd then
			local mergedEnd = math.max(lastEnd, startOffset + length)
			wake._mirrorSpanLengths[spanCount] = mergedEnd - lastStart
			wake._mirrorDirty = true
			return
		end
	end

	if spanCount < wake._mirrorSpanCapacity then
		spanCount += 1
		wake._mirrorSpanOffsets[spanCount] = startOffset
		wake._mirrorSpanLengths[spanCount] = length
		wake._mirrorSpanCount = spanCount
	else
		wake._mirrorSpanOffsets[1] = math.min(wake._mirrorSpanOffsets[1], startOffset)
		local currentEnd = wake._mirrorSpanOffsets[spanCount] + wake._mirrorSpanLengths[spanCount]
		wake._mirrorSpanLengths[1] = math.max(currentEnd, startOffset + length) - wake._mirrorSpanOffsets[1]
		wake._mirrorSpanCount = 1
	end
	wake._mirrorDirty = true
end

local function syncMirrorDescriptor(wake: any, descriptor: any)
	local current = wake._mirrorCurrent
	if current == nil then
		return
	end
	local mirrorEntries = wake._schema.MirrorByDescriptorId[descriptor.id]
	if mirrorEntries == nil then
		return
	end
	for index = 1, #mirrorEntries do
		local entry = mirrorEntries[index]
		copyBytes(current, entry.destOffset, wake._buffer, entry.sourceOffset, entry.size)
		queueMirrorSpan(wake, entry.destOffset, entry.size)
	end
end

local function syncMirrorRange(wake: any, startOffset: number, length: number)
	local current = wake._mirrorCurrent
	if current == nil or length <= 0 then
		return
	end
	perfAdd(wake, "MirrorRangeSyncs", 1)
	local rangeEnd = startOffset + length
	local buckets = wake._schema.MirrorPageBuckets
	if buckets == nil then
		for _, entry in ipairs(wake._schema.MirrorEntries) do
			perfAdd(wake, "MirrorRangeCandidates", 1)
			local overlapStart = math.max(startOffset, entry.sourceOffset)
			local overlapEnd = math.min(rangeEnd, entry.sourceOffset + entry.size)
			if overlapStart < overlapEnd then
				local sourceShift = overlapStart - entry.sourceOffset
				local count = overlapEnd - overlapStart
				copyBytes(current, entry.destOffset + sourceShift, wake._buffer, overlapStart, count)
				queueMirrorSpan(wake, entry.destOffset + sourceShift, count)
				perfAdd(wake, "MirrorRangeApplied", 1)
				perfAdd(wake, "MirrorRangeBytes", count)
			end
		end
		return
	end

	wake._mirrorTouchStamp += 1
	if wake._mirrorTouchStamp >= 2147483647 then
		wake._mirrorTouchStamp = 1
		for index = 1, #wake._mirrorTouchMarks do
			wake._mirrorTouchMarks[index] = 0
		end
	end
	local stamp = wake._mirrorTouchStamp
	local firstPage = math.max(1, math.floor(startOffset / PAGE_SIZE) + 1)
	local lastPage = math.min(#buckets, math.floor((rangeEnd - 1) / PAGE_SIZE) + 1)
	for page = firstPage, lastPage do
		local bucket = buckets[page]
		if bucket ~= nil then
			for index = 1, #bucket do
				local entry = bucket[index]
				if wake._mirrorTouchMarks[entry.id] ~= stamp then
					wake._mirrorTouchMarks[entry.id] = stamp
					perfAdd(wake, "MirrorRangeCandidates", 1)
					local overlapStart = math.max(startOffset, entry.sourceOffset)
					local overlapEnd = math.min(rangeEnd, entry.sourceOffset + entry.size)
					if overlapStart < overlapEnd then
						local sourceShift = overlapStart - entry.sourceOffset
						local count = overlapEnd - overlapStart
						copyBytes(current, entry.destOffset + sourceShift, wake._buffer, overlapStart, count)
						queueMirrorSpan(wake, entry.destOffset + sourceShift, count)
						perfAdd(wake, "MirrorRangeApplied", 1)
						perfAdd(wake, "MirrorRangeBytes", count)
					end
				end
			end
		end
	end
end

local function assignLeaf(wake: any, descriptor: any, value: any)
	assert(wake._view ~= true, "[Merveille/Wake] view wakes are read-only")
	touchDescriptor(wake, descriptor)
	if descriptor.write ~= nil then
		descriptor.write(wake._buffer, value)
	else
		error(`[Merveille/Wake] field '{descriptor.path}' is not directly assignable`)
	end
	markDirtyRange(wake, descriptor.offset, descriptor.size)
	syncMirrorDescriptor(wake, descriptor)
	perfAdd(wake, "PathWrites", 1)
	perfAdd(wake, "PathWriteBytes", descriptor.size)
	bumpRevision(wake)
end

local function buildChildren(wake: any, container: any, map: { [string]: any })
	container._byName = map
	for name, descriptor in map do
		if descriptor.kind == "group" then
			local child = {
				_wake = wake,
				_descriptor = descriptor,
				_byName = descriptor.byName,
				_children = {},
			}
			setmetatable(child, GroupMT)
			buildChildren(wake, child, descriptor.byName)
			container._children[name] = child
		elseif descriptor.kind == "vec" then
			container._children[name] = setmetatable({
				_wake = wake,
				_descriptor = descriptor,
			}, VecMT)
		elseif descriptor.kind == "bits" then
			container._children[name] = setmetatable({
				_wake = wake,
				_descriptor = descriptor,
			}, BitsMT)
		end
	end
end

local function containerIndex(subject: any, methods: { [string]: any }, key: any): any
	if type(key) == "string" then
		local method = methods[key]
		if method ~= nil then
			return method
		end
		if subject._children ~= nil then
			local child = subject._children[key]
			if child ~= nil then
				return child
			end
		end
		local descriptor = subject._byName[key]
		if descriptor ~= nil then
			local wake = subject._wake or subject
			local source = wake._buffer
			if descriptor.read ~= nil then
				return descriptor.read(source)
			elseif descriptor.kind == "group" or descriptor.kind == "vec" or descriptor.kind == "bits" then
				return subject._children[key]
			end
		end
	end
	return rawget(subject, key)
end

local function containerNewIndex(subject: any, key: any, value: any)
	if type(key) == "string" and string.sub(key, 1, 1) == "_" then
		rawset(subject, key, value)
		return
	end
	assert(type(key) == "string", "[Merveille/Wake] invalid field key")
	local descriptor = subject._byName[key]
	assert(descriptor ~= nil, `[Merveille/Wake] unknown field '{tostring(key)}'`)
	assignLeaf(subject._wake or subject, descriptor, value)
end

function Wake.readHeader(source: buffer)
	return {
		magic = buffer.readu32(source, OFF_MAGIC),
		formatVersion = buffer.readu16(source, OFF_FORMAT_VERSION),
		schemaVersion = buffer.readu16(source, OFF_SCHEMA_VERSION),
		schemaHash = buffer.readu32(source, OFF_SCHEMA_HASH),
		pageCount = buffer.readu16(source, OFF_PAGE_COUNT),
		flags = buffer.readu16(source, OFF_FLAGS),
		active = bit32.band(buffer.readu16(source, OFF_FLAGS), FLAG_ACTIVE) ~= 0,
		sealed = bit32.band(buffer.readu16(source, OFF_FLAGS), FLAG_SEALED) ~= 0,
		revision = buffer.readu32(source, OFF_REVISION),
		commit = buffer.readu32(source, OFF_COMMIT),
		lockEpoch = buffer.readu32(source, OFF_LOCK_EPOCH),
		openUnix = buffer.readu32(source, OFF_OPEN_UNIX),
		lastSaveUnix = buffer.readu32(source, OFF_LAST_SAVE_UNIX),
		bodyBytes = buffer.readu32(source, OFF_BODY_BYTES),
		bodyCRC32 = buffer.readu32(source, OFF_BODY_CRC32),
		ownerPlaceId = buffer.readu32(source, OFF_OWNER_PLACE),
		ownerJobId = Text.readFixed(source, OFF_OWNER_JOB, HEADER_OWNER_JOB_MAX),
		schemaId = Text.readFixed(source, OFF_SCHEMA_ID, HEADER_SCHEMA_ID_MAX),
		mirrorRevision = buffer.readu32(source, OFF_MIRROR_REVISION),
		sealVersion = buffer.readu16(source, OFF_SEAL_VERSION),
	}
end

function Wake.seal(target: buffer, schema: any, state: { [string]: any })
	buffer.writeu32(target, OFF_MAGIC, MAGIC)
	buffer.writeu16(target, OFF_FORMAT_VERSION, FORMAT_VERSION)
	buffer.writeu16(target, OFF_SCHEMA_VERSION, schema.Version)
	buffer.writeu32(target, OFF_SCHEMA_HASH, schema.Hash)
	buffer.writeu16(target, OFF_PAGE_COUNT, schema.Pages)
	buffer.writeu16(
		target,
		OFF_FLAGS,
		bit32.bor(if state.active then FLAG_ACTIVE else 0, if state.sealed then FLAG_SEALED else 0)
	)
	buffer.writeu32(target, OFF_REVISION, state.revision or 0)
	buffer.writeu32(target, OFF_COMMIT, state.commit or 0)
	buffer.writeu32(target, OFF_LOCK_EPOCH, state.lockEpoch or 0)
	buffer.writeu32(target, OFF_OPEN_UNIX, state.openUnix or 0)
	buffer.writeu32(target, OFF_LAST_SAVE_UNIX, state.lastSaveUnix or 0)
	buffer.writeu32(target, OFF_BODY_BYTES, schema.PageBytes)
	buffer.writeu32(target, OFF_OWNER_PLACE, state.ownerPlaceId or 0)
	Text.writeFixed(target, OFF_OWNER_JOB, HEADER_OWNER_JOB_MAX, state.ownerJobId or "")
	Text.writeFixed(target, OFF_SCHEMA_ID, HEADER_SCHEMA_ID_MAX, schema.Id)
	buffer.writeu32(target, OFF_MIRROR_REVISION, state.mirrorRevision or 0)
	buffer.writeu16(target, OFF_SEAL_VERSION, state.sealVersion or 0)
	for index = 0, 15 do
		buffer.writeu8(target, OFF_SEAL_NONCE + index, 0)
	end
	for index = 0, 31 do
		buffer.writeu8(target, OFF_SEAL_MAC + index, 0)
	end

	buffer.writeu32(target, OFF_BODY_CRC32, 0)
	local crc = CRC32.compute(target, HEADER_SIZE, schema.PageBytes - HEADER_SIZE)
	buffer.writeu32(target, OFF_BODY_CRC32, crc)
end

function Wake.verifyIntegrity(source: buffer, schema: any?): (boolean, string?)
	if buffer.len(source) < HEADER_SIZE then
		return false, "buffer shorter than header"
	end
	local header = Wake.readHeader(source)
	if header.magic ~= MAGIC then
		return false, "bad magic"
	end
	if schema ~= nil then
		if header.schemaId ~= schema.Id then
			return false, "schema id mismatch"
		end
		if header.schemaVersion ~= schema.Version then
			return false, "schema version mismatch"
		end
		if header.pageCount ~= schema.Pages then
			return false, "page count mismatch"
		end
	end
	local saved = header.bodyCRC32
	buffer.writeu32(source, OFF_BODY_CRC32, 0)
	local actual = CRC32.compute(source, HEADER_SIZE, buffer.len(source) - HEADER_SIZE)
	buffer.writeu32(source, OFF_BODY_CRC32, saved)
	if actual ~= saved then
		return false, "crc mismatch"
	end
	return true, nil
end

function Wake.newBuffer(schema: any): buffer
	local out = buffer.create(schema.PageBytes)
	for _, descriptor in ipairs(schema.Descriptors) do
		if descriptor.kind == "vec" then
			buffer.writeu16(out, descriptor.offset, 0)
			buffer.writeu16(out, descriptor.offset + 2, descriptor.capacity)
		end
	end
	return out
end

local function seedIntoBuffer(target: buffer, descriptor: any, value: any)
	if descriptor.kind == "scalar" then
		writeScalar(target, descriptor.scalar, descriptor.offset, value)
	elseif descriptor.kind == "text" then
		Text.writeFixed(target, descriptor.offset, descriptor.maxBytes, value)
	elseif descriptor.kind == "group" then
		for childName, childValue in value do
			local childDescriptor = descriptor.byName[childName]
			if childDescriptor ~= nil then
				seedIntoBuffer(target, childDescriptor, childValue)
			end
		end
	elseif descriptor.kind == "bits" then
		for bitName, enabled in value do
			local position = if type(bitName) == "string" then descriptor.map[bitName] else bitName - 1
			if position ~= nil then
				local byteOffset = descriptor.offset + math.floor(position / 8)
				local bitOffset = position % 8
				local current = buffer.readu8(target, byteOffset)
				local mask = bit32.lshift(1, bitOffset)
				buffer.writeu8(
					target,
					byteOffset,
					if enabled then bit32.bor(current, mask) else bit32.band(current, bit32.bnot(mask))
				)
			end
		end
	elseif descriptor.kind == "blob" then
		if type(value) == "string" then
			local count = math.min(descriptor.size, #value)
			for index = 0, count - 1 do
				buffer.writeu8(target, descriptor.offset + index, string.byte(value, index + 1))
			end
		elseif typeof(value) == "buffer" then
			copyBytes(target, descriptor.offset, value, 0, math.min(descriptor.size, buffer.len(value)))
		end
	elseif descriptor.kind == "vec" then
		local count = 0
		for index, item in ipairs(value) do
			if index > descriptor.capacity then
				break
			end
			count += 1
			writeScalar(target, descriptor.element, descriptor.offset + 4 + (index - 1) * descriptor.elementWidth, item)
		end
		buffer.writeu16(target, descriptor.offset, count)
		buffer.writeu16(target, descriptor.offset + 2, descriptor.capacity)
	end
end

function Wake.applyDefaults(schema: any, target: buffer)
	for name, value in schema.Defaults do
		local descriptor = schema.RootByName[name]
		if descriptor ~= nil then
			seedIntoBuffer(target, descriptor, value)
		end
	end
end

local function rebuildMirrorBuffers(wake: any)
	if wake._mirrorCurrent == nil then
		return
	end
	for _, entry in ipairs(wake._schema.MirrorEntries) do
		copyBytes(wake._mirrorCurrent, entry.destOffset, wake._buffer, entry.sourceOffset, entry.size)
	end
end

function Wake.fromBuffer(store: any, key: string, player: Player?, source: buffer, active: boolean, viewMode: boolean)
	local header = Wake.readHeader(source)
	local wake = {
		_schema = store.Schema,
		_store = store,
		_key = key,
		_player = player,
		_buffer = source,
		_saveScratch = if viewMode then nil else buffer.create(store.Schema.PageBytes),
		_byName = store.Schema.RootByName,
		_fieldDirty = buffer.create(math.max(1, math.ceil(store.Schema.FieldCount / 8))),
		_pageDirty = buffer.create(math.max(1, math.ceil(store.Schema.Pages / 8))),
		_spanOffsets = table.create(128, 0),
		_spanLengths = table.create(128, 0),
		_spanCapacity = 128,
		_spanCount = 0,
		_mirrorSpanOffsets = table.create(64, 0),
		_mirrorSpanLengths = table.create(64, 0),
		_mirrorSpanCapacity = 64,
		_mirrorSpanCount = 0,
		_mirrorDirty = false,
		_mirrorBaselineRevision = header.mirrorRevision,
		_lastKeyframeAt = 0,
		_lastKeyframeRevision = header.mirrorRevision,
		_children = {},
		_dirty = false,
		_revision = header.revision,
		_commit = header.commit,
		_lockEpoch = header.lockEpoch,
		_openUnix = header.openUnix,
		_lastSaveUnix = header.lastSaveUnix,
		_active = active,
		_view = viewMode,
		_saving = false,
		_releasing = false,
		_mirrorCurrent = if store.Schema.MirrorSize > 0 then buffer.create(store.Schema.MirrorSize) else nil,
		_mirrorPrevious = if store.Schema.MirrorSize > 0 then buffer.create(store.Schema.MirrorSize) else nil,
		_mirrorPacket = if store.Schema.MirrorSize > 0
			then buffer.create(math.max(64, 1 + 4 + 4 + 2 + store.Schema.MirrorSize * 5))
			else nil,
		_mirrorTouchMarks = table.create(#store.Schema.MirrorEntries, 0),
		_mirrorTouchStamp = 0,
		_perf = if store.Options.profile
			then {
				PathWrites = 0,
				PathWriteBytes = 0,
				VectorWrites = 0,
				VectorWriteBytes = 0,
				BitsWrites = 0,
				RawWrites = 0,
				RawWriteBytes = 0,
				BlobWrites = 0,
				BlobWriteBytes = 0,
				NumericOps = 0,
				ToggleOps = 0,
				CompareExchanges = 0,
				Keyframes = 0,
				Deltas = 0,
				Xors = 0,
				PacketBytes = 0,
				DirtySpanPeak = 0,
				MirrorSpanPeak = 0,
				MirrorRangeSyncs = 0,
				MirrorRangeCandidates = 0,
				MirrorRangeApplied = 0,
				MirrorRangeBytes = 0,
				saves = {
					count = 0,
					ok = 0,
					err = 0,
					total = 0,
					max = 0,
					bytes = 0,
				},
			}
			else nil,
	}
	setmetatable(wake, WakeMT)
	buildChildren(wake, wake, store.Schema.RootByName)
	if wake._mirrorCurrent ~= nil then
		rebuildMirrorBuffers(wake)
		copyBytes(wake._mirrorPrevious, 0, wake._mirrorCurrent, 0, store.Schema.MirrorSize)
	end
	return wake
end

function WAKE_METHODS.vesper(self: any): boolean
	return self._store:_saveWake(self, false, "Manual")
end

function WAKE_METHODS.flush(self: any): boolean
	return self:vesper()
end

function WAKE_METHODS.save(self: any): boolean
	return self:flush()
end

function WAKE_METHODS.requiem(self: any, reason: string?): boolean
	return self._store:_saveWake(self, true, reason or "Manual")
end

function WAKE_METHODS.release(self: any, reason: string?): boolean
	return self:requiem(reason)
end

function WAKE_METHODS.close(self: any, reason: string?): boolean
	return self:release(reason)
end

function WAKE_METHODS.veille(self: any): boolean
	return self._active == true and self._view ~= true
end

function WAKE_METHODS.active(self: any): boolean
	return self:veille()
end

function WAKE_METHODS.isActive(self: any): boolean
	return self:active()
end

function WAKE_METHODS.revision(self: any): number
	return self._revision
end

function WAKE_METHODS.commit(self: any): number
	return self._commit
end

function WAKE_METHODS.key(self: any): string
	return self._key
end

function WAKE_METHODS.player(self: any): Player?
	return self._player
end

function WAKE_METHODS.sigil(self: any, path: string): number
	return self:rawOffset(path)
end

function WAKE_METHODS.offset(self: any, path: string): number
	return self:sigil(path)
end

function WAKE_METHODS.rawOffset(self: any, path: string): number
	local descriptor = self._schema.ByPath[path]
	assert(descriptor ~= nil, `[Merveille/Wake] unknown path '{path}'`)
	return descriptor.offset
end

function WAKE_METHODS.folio(self: any, index: number): (buffer, number, number)
	return self:rawPage(index)
end

function WAKE_METHODS.page(self: any, index: number): (buffer, number, number)
	return self:folio(index)
end

function WAKE_METHODS.rawPage(self: any, index: number): (buffer, number, number)
	assert(index >= 1 and index <= self._schema.Pages, `[Merveille/Wake] page index {index} out of range`)
	local offset = (index - 1) * PAGE_SIZE
	return self._buffer, offset, PAGE_SIZE
end

function WAKE_METHODS.lane(self: any, path: string): (buffer, number, number)
	local descriptor = self._schema.ByPath[path]
	assert(descriptor ~= nil, `[Merveille/Wake] unknown path '{path}'`)
	assert(descriptor.kind ~= "group", `[Merveille/Wake] path '{path}' cannot point at a group lane directly`)
	return self._buffer, descriptor.offset, descriptor.size
end

function WAKE_METHODS.rawLane(self: any, path: string): (buffer, number, number)
	return self:lane(path)
end

function WAKE_METHODS.rawBytes(self: any, offset: number, length: number): buffer
	assert(
		offset >= 0 and length >= 0 and offset + length <= buffer.len(self._buffer),
		"[Merveille/Wake] rawBytes out of range"
	)
	local out = buffer.create(length)
	copyBytes(out, 0, self._buffer, offset, length)
	return out
end

function WAKE_METHODS.writeBytes(self: any, offset: number, source: any, sourceOffset: number?, length: number?): number
	assert(self._view ~= true, "[Merveille/Wake] view wakes are read-only")
	local start = if sourceOffset == nil then 0 else sourceOffset
	local count = if length == nil
		then (if type(source) == "string" then #source - start else buffer.len(source) - start)
		else length
	assert(
		offset >= self._schema.HeaderBytes and count >= 0 and offset + count <= buffer.len(self._buffer),
		"[Merveille/Wake] writeBytes out of range"
	)
	if type(source) == "string" then
		for index = 0, count - 1 do
			buffer.writeu8(self._buffer, offset + index, string.byte(source, start + index + 1))
		end
	else
		assert(typeof(source) == "buffer", "[Merveille/Wake] writeBytes expects string or buffer")
		copyBytes(self._buffer, offset, source, start, count)
	end
	self._dirty = true
	markDirtyRange(self, offset, count)
	syncMirrorRange(self, offset, count)
	perfAdd(self, "RawWrites", 1)
	perfAdd(self, "RawWriteBytes", count)
	bumpRevision(self)
	return count
end

function WAKE_METHODS.zero(self: any, offset: number, length: number): number
	assert(self._view ~= true, "[Merveille/Wake] view wakes are read-only")
	assert(
		offset >= self._schema.HeaderBytes and length >= 0 and offset + length <= buffer.len(self._buffer),
		"[Merveille/Wake] zero out of range"
	)
	fillBytes(self._buffer, offset, length, 0)
	self._dirty = true
	markDirtyRange(self, offset, length)
	syncMirrorRange(self, offset, length)
	perfAdd(self, "RawWrites", 1)
	perfAdd(self, "RawWriteBytes", length)
	bumpRevision(self)
	return length
end

local function pathValue(subject: any, path: string)
	local cursor = subject
	local start = 1
	while true do
		local stop = string.find(path, ".", start, true)
		if stop == nil then
			return cursor[string.sub(path, start)]
		end
		cursor = cursor[string.sub(path, start, stop - 1)]
		assert(cursor ~= nil, `[Merveille/Wake] unknown path '{path}'`)
		start = stop + 1
	end
end

local function pathParent(subject: any, path: string): (any, string)
	local cursor = subject
	local start = 1
	while true do
		local stop = string.find(path, ".", start, true)
		if stop == nil then
			return cursor, string.sub(path, start)
		end
		cursor = cursor[string.sub(path, start, stop - 1)]
		assert(cursor ~= nil, `[Merveille/Wake] unknown path '{path}'`)
		start = stop + 1
	end
end

local function scalarDescriptor(wake: any, path: string)
	local descriptor = wake._schema.ByPath[path]
	assert(descriptor ~= nil, `[Merveille/Wake] unknown path '{path}'`)
	assert(descriptor.kind == "scalar", `[Merveille/Wake] path '{path}' is not a scalar field`)
	return descriptor
end

function WAKE_METHODS.read(self: any, path: string)
	local descriptor = self._schema.ByPath[path]
	if descriptor ~= nil and descriptor.kind ~= "group" and descriptor.read ~= nil then
		return descriptor.read(self._buffer)
	end
	return pathValue(self, path)
end

function WAKE_METHODS.write(self: any, path: string, value: any)
	local descriptor = self._schema.ByPath[path]
	if descriptor ~= nil and descriptor.kind ~= "group" then
		assignLeaf(self, descriptor, value)
		return value
	end
	local parent, name = pathParent(self, path)
	parent[name] = value
	return value
end

function WAKE_METHODS.add(self: any, path: string, value: number): number
	perfAdd(self, "NumericOps", 1)
	local descriptor = scalarDescriptor(self, path)
	local nextValue = (descriptor.read(self._buffer) :: number) + value
	assignLeaf(self, descriptor, nextValue)
	return nextValue
end

function WAKE_METHODS.sub(self: any, path: string, value: number): number
	return self:add(path, -value)
end

function WAKE_METHODS.max(self: any, path: string, value: number): number
	perfAdd(self, "NumericOps", 1)
	local descriptor = scalarDescriptor(self, path)
	local nextValue = math.max(descriptor.read(self._buffer), value)
	assignLeaf(self, descriptor, nextValue)
	return nextValue
end

function WAKE_METHODS.min(self: any, path: string, value: number): number
	perfAdd(self, "NumericOps", 1)
	local descriptor = scalarDescriptor(self, path)
	local nextValue = math.min(descriptor.read(self._buffer), value)
	assignLeaf(self, descriptor, nextValue)
	return nextValue
end

function WAKE_METHODS.clamp(self: any, path: string, low: number, high: number): number
	perfAdd(self, "NumericOps", 1)
	local descriptor = scalarDescriptor(self, path)
	local current = descriptor.read(self._buffer)
	local nextValue = math.max(low, math.min(high, current))
	assignLeaf(self, descriptor, nextValue)
	return nextValue
end

function WAKE_METHODS.toggle(self: any, path: string, state: boolean?): boolean
	perfAdd(self, "ToggleOps", 1)
	local current = pathValue(self, path)
	assert(type(current) == "boolean", `[Merveille/Wake] path '{path}' is not a boolean field`)
	local nextValue = if state == nil then not current else state
	self:write(path, nextValue)
	return nextValue
end

function WAKE_METHODS.compareExchange(self: any, path: string, expected: any, nextValue: any): boolean
	perfAdd(self, "CompareExchanges", 1)
	local current = self:read(path)
	if current ~= expected then
		return false
	end
	self:write(path, nextValue)
	return true
end

function WAKE_METHODS.blob(self: any, path: string): buffer
	local descriptor = self._schema.ByPath[path]
	assert(descriptor ~= nil and descriptor.kind == "blob", `[Merveille/Wake] path '{path}' is not a blob field`)
	return descriptor.read(self._buffer)
end

function WAKE_METHODS.writeBlob(self: any, path: string, value: any, sourceOffset: number?, length: number?): number
	local descriptor = self._schema.ByPath[path]
	assert(descriptor ~= nil and descriptor.kind == "blob", `[Merveille/Wake] path '{path}' is not a blob field`)
	assert(self._view ~= true, "[Merveille/Wake] view wakes are read-only")
	if sourceOffset == nil and length == nil then
		assignLeaf(self, descriptor, value)
		perfAdd(self, "BlobWrites", 1)
		perfAdd(self, "BlobWriteBytes", descriptor.size)
		return descriptor.size
	end
	touchDescriptor(self, descriptor)
	local start = if sourceOffset == nil then 0 else sourceOffset
	local available = if type(value) == "string" then #value - start else buffer.len(value) - start
	local count = math.max(0, math.min(descriptor.size, if length == nil then available else length))
	if type(value) == "string" then
		for index = 0, count - 1 do
			buffer.writeu8(self._buffer, descriptor.offset + index, string.byte(value, start + index + 1))
		end
	else
		assert(typeof(value) == "buffer", "[Merveille/Wake] writeBlob expects string or buffer")
		copyBytes(self._buffer, descriptor.offset, value, start, count)
	end
	self._dirty = true
	markDirtyRange(self, descriptor.offset, count)
	syncMirrorRange(self, descriptor.offset, count)
	perfAdd(self, "BlobWrites", 1)
	perfAdd(self, "BlobWriteBytes", count)
	bumpRevision(self)
	return count
end

function WAKE_METHODS.trySave(self: any)
	local ok, saved = pcall(self.save, self)
	if not ok then
		return Result.err(saved)
	end
	return if saved then Result.ok(self) else Result.err("SaveFailed")
end

function WAKE_METHODS.matchSave(self: any, onOk: (any) -> any, onErr: (any) -> any)
	return self:trySave():match(onOk, onErr)
end

function WAKE_METHODS.tryClose(self: any, reason: string?)
	local ok, closed = pcall(self.close, self, reason)
	if not ok then
		return Result.err(closed)
	end
	return if closed then Result.ok(self) else Result.err("CloseFailed")
end

function WAKE_METHODS.matchClose(self: any, onOk: (any) -> any, onErr: (any) -> any, reason: string?)
	return self:tryClose(reason):match(onOk, onErr)
end

function WAKE_METHODS.tryMiroir(self: any)
	local ok, packet, length = pcall(self.miroir, self)
	if not ok then
		return Result.err(packet)
	end
	if packet ~= nil and length > 0 then
		return Result.ok(table.freeze({
			Buffer = packet,
			Length = length,
			Kind = "Delta",
		}))
	end
	return Result.err("NoMirrorPacket")
end

function WAKE_METHODS.matchMiroir(self: any, onOk: (any) -> any, onErr: (any) -> any)
	return self:tryMiroir():match(onOk, onErr)
end

function WAKE_METHODS.buildMirrorFull(self: any): (buffer?, number)
	if self._mirrorCurrent == nil then
		return nil, 0
	end
	rebuildMirrorBuffers(self)
	local packet = self._mirrorPacket :: buffer
	buffer.writeu8(packet, 0, 1)
	buffer.writeu32(packet, 1, self._revision)
	buffer.writeu32(packet, 5, self._schema.MirrorSize)
	copyBytes(packet, 9, self._mirrorCurrent, 0, self._schema.MirrorSize)
	copyBytes(self._mirrorPrevious :: buffer, 0, self._mirrorCurrent, 0, self._schema.MirrorSize)
	self._mirrorBaselineRevision = self._revision
	self._lastKeyframeRevision = self._revision
	self._lastKeyframeAt = os.clock()
	local packetBytes = 9 + self._schema.MirrorSize
	perfPacket(self, "Keyframes", packetBytes)
	self:_clearMirror()
	return packet, packetBytes
end

function WAKE_METHODS.buildMirrorDelta(self: any): (buffer?, number)
	if self._mirrorCurrent == nil then
		return nil, 0
	end

	local packet = self._mirrorPacket :: buffer
	local current = self._mirrorCurrent :: buffer
	local previous = self._mirrorPrevious :: buffer

	buffer.writeu8(packet, 0, 2)
	buffer.writeu32(packet, 1, self._revision)
	buffer.writeu32(packet, 5, self._mirrorBaselineRevision)
	buffer.writeu16(packet, 9, self._mirrorSpanCount)

	local writeOffset = 11
	for spanIndex = 1, self._mirrorSpanCount do
		local start = self._mirrorSpanOffsets[spanIndex]
		local length = self._mirrorSpanLengths[spanIndex]
		buffer.writeu16(packet, writeOffset, start)
		buffer.writeu16(packet, writeOffset + 2, length)
		copyBytes(packet, writeOffset + 4, current, start, length)
		copyBytes(previous, start, current, start, length)
		writeOffset += 4 + length
	end

	self._mirrorBaselineRevision = self._revision
	perfPacket(self, "Deltas", writeOffset)
	self:_clearMirror()
	return packet, writeOffset
end

function WAKE_METHODS.buildMirrorXor(self: any): (buffer?, number)
	if self._mirrorCurrent == nil then
		return nil, 0
	end

	local packet = self._mirrorPacket :: buffer
	local current = self._mirrorCurrent :: buffer
	local previous = self._mirrorPrevious :: buffer

	buffer.writeu8(packet, 0, 3)
	buffer.writeu32(packet, 1, self._revision)
	buffer.writeu32(packet, 5, self._mirrorBaselineRevision)
	buffer.writeu16(packet, 9, self._mirrorSpanCount)

	local writeOffset = 11
	for spanIndex = 1, self._mirrorSpanCount do
		local start = self._mirrorSpanOffsets[spanIndex]
		local length = self._mirrorSpanLengths[spanIndex]
		buffer.writeu16(packet, writeOffset, start)
		buffer.writeu16(packet, writeOffset + 2, length)
		Xor.span(packet, writeOffset + 4, current, start, previous, start, length)
		copyBytes(previous, start, current, start, length)
		writeOffset += 4 + length
	end

	self._mirrorBaselineRevision = self._revision
	perfPacket(self, "Xors", writeOffset)
	self:_clearMirror()
	return packet, writeOffset
end

function WAKE_METHODS.unreliable(self: any, keyframeEvery: number?, nowClock: number?): (buffer?, number, string)
	if self._mirrorCurrent == nil then
		return nil, 0, "None"
	end
	local interval = if keyframeEvery == nil then 1 else keyframeEvery
	local stamp = if nowClock == nil then os.clock() else nowClock
	if interval <= 0 or self._lastKeyframeAt == 0 or stamp - self._lastKeyframeAt >= interval then
		self._lastKeyframeAt = stamp
		local packet, length = self:buildMirrorFull()
		return packet, length, "Keyframe"
	end
	local packet, length = self:buildMirrorXor()
	return packet, length, "Xor"
end

function WAKE_METHODS.keyframe(self: any): (buffer?, number)
	return self:buildMirrorFull()
end

function WAKE_METHODS.xor(self: any): (buffer?, number)
	return self:buildMirrorXor()
end

function WAKE_METHODS.pulse(self: any): (buffer?, number)
	return self:buildMirrorDelta()
end

function WAKE_METHODS.mirror(self: any): (buffer?, number)
	return self:pulse()
end

function WAKE_METHODS.miroir(self: any): (buffer?, number)
	return self:mirror()
end

function WAKE_METHODS.miroirUnreliable(self: any, keyframeEvery: number?, nowClock: number?): (buffer?, number, string)
	return self:unreliable(keyframeEvery, nowClock)
end

function WAKE_METHODS._clearMirror(self: any)
	self._mirrorSpanCount = 0
	self._mirrorDirty = false
end

function WAKE_METHODS._clearDirty(self: any)
	clearBytes(self._fieldDirty)
	clearBytes(self._pageDirty)
	self._dirty = false
	self._spanCount = 0
	self:_clearMirror()
end

function WAKE_METHODS._deactivate(self: any)
	self._active = false
	self._releasing = false
end

function VECTOR_METHODS.clear(self: any)
	assert(self._wake._view ~= true, "[Merveille/Vector] view wakes are read-only")
	local descriptor = self._descriptor
	local count = buffer.readu16(self._wake._buffer, descriptor.offset)
	if count == 0 then
		return
	end
	buffer.writeu16(self._wake._buffer, descriptor.offset, 0)
	for index = 1, count do
		writeScalar(
			self._wake._buffer,
			descriptor.element,
			descriptor.offset + 4 + (index - 1) * descriptor.elementWidth,
			0
		)
	end
	touchDescriptor(self._wake, descriptor)
	markDirtyRange(self._wake, descriptor.offset, descriptor.size)
	syncMirrorDescriptor(self._wake, descriptor)
	perfAdd(self._wake, "VectorWrites", 1)
	perfAdd(self._wake, "VectorWriteBytes", descriptor.size)
	bumpRevision(self._wake)
end

function VECTOR_METHODS.size(self: any): number
	return buffer.readu16(self._wake._buffer, self._descriptor.offset)
end

function VECTOR_METHODS.empty(self: any): boolean
	return self:size() == 0
end

function VECTOR_METHODS.at(self: any, index: number): any
	return self[index]
end

function VECTOR_METHODS.last(self: any): any
	local count = self:size()
	if count <= 0 then
		return nil
	end
	return self[count]
end

function VECTOR_METHODS.push(self: any, value: any): number
	local nextIndex = self:size() + 1
	self[nextIndex] = value
	return nextIndex
end

function VECTOR_METHODS.pop(self: any): any
	local count = self:size()
	if count <= 0 then
		return nil
	end
	local value = self[count]
	self[count] = nil
	return value
end

function VECTOR_METHODS.find(self: any, wanted: any): number?
	local descriptor = self._descriptor
	local count = buffer.readu16(self._wake._buffer, descriptor.offset)
	for index = 1, count do
		if
			readScalar(
				self._wake._buffer,
				descriptor.element,
				descriptor.offset + 4 + (index - 1) * descriptor.elementWidth
			) == wanted
		then
			return index
		end
	end
	return nil
end

function VECTOR_METHODS.contains(self: any, wanted: any): boolean
	return self:find(wanted) ~= nil
end

WakeMT.__index = function(self, key)
	return containerIndex(self, WAKE_METHODS, key)
end
WakeMT.__newindex = containerNewIndex

GroupMT.__index = function(self, key)
	return containerIndex(self, GROUP_METHODS, key)
end
GroupMT.__newindex = containerNewIndex

VecMT.__index = function(self, key)
	if type(key) == "string" then
		if key == "Count" then
			return buffer.readu16(self._wake._buffer, self._descriptor.offset)
		elseif key == "Capacity" then
			return self._descriptor.capacity
		end
		local method = VECTOR_METHODS[key]
		if method ~= nil then
			return method
		end
		return rawget(self, key)
	elseif type(key) == "number" then
		assert(key % 1 == 0, "[Merveille/Vector] vector indices must be integers")
		local count = buffer.readu16(self._wake._buffer, self._descriptor.offset)
		if key < 1 or key > count then
			return nil
		end
		local slotOffset = self._descriptor.offset + 4 + (key - 1) * self._descriptor.elementWidth
		return readScalar(self._wake._buffer, self._descriptor.element, slotOffset)
	end
	return nil
end

VecMT.__newindex = function(self, key, value)
	if type(key) == "string" and string.sub(key, 1, 1) == "_" then
		rawset(self, key, value)
		return
	end
	assert(type(key) == "number" and key % 1 == 0, "[Merveille/Vector] vector writes must use integer indices")
	assert(self._wake._view ~= true, "[Merveille/Vector] view wakes are read-only")

	local descriptor = self._descriptor
	local count = buffer.readu16(self._wake._buffer, descriptor.offset)
	local cap = descriptor.capacity
	assert(key >= 1 and key <= count + 1, `[Merveille/Vector] index {key} out of range`)

	touchDescriptor(self._wake, descriptor)

	if value == nil then
		assert(key <= count, `[Merveille/Vector] cannot remove missing index {key}`)
		for index = key, count - 1 do
			local nextOffset = descriptor.offset + 4 + index * descriptor.elementWidth
			local currentOffset = descriptor.offset + 4 + (index - 1) * descriptor.elementWidth
			local nextValue = readScalar(self._wake._buffer, descriptor.element, nextOffset)
			writeScalar(self._wake._buffer, descriptor.element, currentOffset, nextValue)
		end
		writeScalar(
			self._wake._buffer,
			descriptor.element,
			descriptor.offset + 4 + (count - 1) * descriptor.elementWidth,
			0
		)
		buffer.writeu16(self._wake._buffer, descriptor.offset, count - 1)
		markDirtyRange(self._wake, descriptor.offset, descriptor.size)
		syncMirrorDescriptor(self._wake, descriptor)
		perfAdd(self._wake, "VectorWrites", 1)
		perfAdd(self._wake, "VectorWriteBytes", descriptor.size)
		bumpRevision(self._wake)
		return
	end

	if key == count + 1 then
		assert(count < cap, `[Merveille/Vector] vec '{descriptor.path}' exceeded capacity {cap}`)
		buffer.writeu16(self._wake._buffer, descriptor.offset, count + 1)
	end

	local slotOffset = descriptor.offset + 4 + (key - 1) * descriptor.elementWidth
	writeScalar(self._wake._buffer, descriptor.element, slotOffset, value)
	markDirtyRange(self._wake, descriptor.offset, 2)
	markDirtyRange(self._wake, slotOffset, descriptor.elementWidth)
	syncMirrorDescriptor(self._wake, descriptor)
	bumpRevision(self._wake)
end

BitsMT.__index = function(self, key)
	if type(key) == "string" then
		if string.sub(key, 1, 1) == "_" then
			return rawget(self, key)
		end
		local method = BITS_METHODS[key]
		if method ~= nil then
			return method
		end
	end

	local descriptor = self._descriptor
	local position = if type(key) == "number" then key else descriptor.map[key]
	if position == nil then
		return nil
	end
	local byteOffset = descriptor.offset + math.floor(position / 8)
	local bitOffset = position % 8
	local current = buffer.readu8(self._wake._buffer, byteOffset)
	return bit32.band(current, bit32.lshift(1, bitOffset)) ~= 0
end

BitsMT.__newindex = function(self, key, value)
	if type(key) == "string" and string.sub(key, 1, 1) == "_" then
		rawset(self, key, value)
		return
	end
	assert(self._wake._view ~= true, "[Merveille/Bits] view wakes are read-only")
	local descriptor = self._descriptor
	local position = if type(key) == "number" then key else descriptor.map[key]
	assert(position ~= nil, `[Merveille/Bits] unknown bit '{tostring(key)}'`)
	local byteOffset = descriptor.offset + math.floor(position / 8)
	local bitOffset = position % 8
	local current = buffer.readu8(self._wake._buffer, byteOffset)
	local mask = bit32.lshift(1, bitOffset)
	local nextValue = if value then bit32.bor(current, mask) else bit32.band(current, bit32.bnot(mask))
	if nextValue ~= current then
		touchDescriptor(self._wake, descriptor)
		buffer.writeu8(self._wake._buffer, byteOffset, nextValue)
		markDirtyRange(self._wake, byteOffset, 1)
		syncMirrorDescriptor(self._wake, descriptor)
		perfAdd(self._wake, "BitsWrites", 1)
		bumpRevision(self._wake)
	end
end

for kind, reader in SCALAR_READERS do
	local suffix = string.upper(string.sub(kind, 1, 1)) .. string.sub(kind, 2)
	WAKE_METHODS[`raw{suffix}`] = function(self: any, offset: number)
		return reader(self._buffer, offset)
	end
end

for kind, writer in SCALAR_WRITERS do
	local suffix = string.upper(string.sub(kind, 1, 1)) .. string.sub(kind, 2)
	WAKE_METHODS[`write{suffix}`] = function(self: any, offset: number, value: any)
		assert(self._view ~= true, "[Merveille/Wake] view wakes are read-only")
		assert(
			offset >= self._schema.HeaderBytes and offset + SCALAR_WIDTHS[kind] <= buffer.len(self._buffer),
			"[Merveille/Wake] raw scalar write out of range"
		)
		writer(self._buffer, offset, value)
		self._dirty = true
		markDirtyRange(self, offset, SCALAR_WIDTHS[kind])
		syncMirrorRange(self, offset, SCALAR_WIDTHS[kind])
		perfAdd(self, "RawWrites", 1)
		perfAdd(self, "RawWriteBytes", SCALAR_WIDTHS[kind])
		bumpRevision(self)
		return value
	end
end

WAKE_METHODS.rawBool = function(self: any, offset: number)
	return buffer.readu8(self._buffer, offset) ~= 0
end

WAKE_METHODS.writeBool = function(self: any, offset: number, value: boolean)
	assert(self._view ~= true, "[Merveille/Wake] view wakes are read-only")
	assert(
		offset >= self._schema.HeaderBytes and offset + 1 <= buffer.len(self._buffer),
		"[Merveille/Wake] raw bool write out of range"
	)
	buffer.writeu8(self._buffer, offset, value and 1 or 0)
	self._dirty = true
	markDirtyRange(self, offset, 1)
	syncMirrorRange(self, offset, 1)
	perfAdd(self, "RawWrites", 1)
	perfAdd(self, "RawWriteBytes", 1)
	bumpRevision(self)
	return value
end

return table.freeze(Wake)
