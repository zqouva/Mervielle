--!strict

-->	["arena"]
-->	Reusable scratch buffers.
-->	Phase 3 asks for scratch arenas instead of one-off temporary allocations.
-->	This module gives that surface now so replication, save encoding, and tools
-->	can share a steady buffer pool.

local Arena = {}
Arena.__index = Arena

function Arena.new(byteSize: number, slotCount: number?)
	assert(
		type(byteSize) == "number" and byteSize % 1 == 0 and byteSize > 0,
		"[Merveille/Arena] byteSize must be a positive integer"
	)
	local slots = if slotCount == nil then 1 else slotCount
	assert(
		type(slots) == "number" and slots % 1 == 0 and slots > 0,
		"[Merveille/Arena] slotCount must be a positive integer"
	)

	local free = table.create(slots)
	for index = 1, slots do
		free[index] = buffer.create(byteSize)
	end

	return setmetatable({
		ByteSize = byteSize,
		SlotCount = slots,
		FreeCount = slots,
		OverflowCount = 0,
		_peak = 0,
		_free = free,
	}, Arena)
end

function Arena:take(): buffer
	local free = self._free
	local count = #free
	if count > 0 then
		local lane = free[count]
		free[count] = nil
		self.FreeCount = count - 1
		local inUse = self.SlotCount - self.FreeCount
		if inUse > self._peak then
			self._peak = inUse
		end
		return lane
	end
	self.OverflowCount += 1
	local inUse = self.SlotCount + self.OverflowCount
	if inUse > self._peak then
		self._peak = inUse
	end
	return buffer.create(self.ByteSize)
end

function Arena:give(lane: buffer)
	assert(buffer.len(lane) == self.ByteSize, "[Merveille/Arena] returned buffer has the wrong byte size")
	if self.OverflowCount > 0 and self.FreeCount >= self.SlotCount then
		self.OverflowCount -= 1
		return
	end
	if self.FreeCount < self.SlotCount then
		local free = self._free
		free[#free + 1] = lane
		self.FreeCount += 1
	end
end

function Arena:use(fn: (buffer) -> any)
	local lane = self:take()
	local ok, value = pcall(fn, lane)
	self:give(lane)
	if ok then
		return value
	end
	error(value)
end

function Arena:stats()
	return {
		byteSize = self.ByteSize,
		slots = self.SlotCount,
		free = self.FreeCount,
		overflow = self.OverflowCount,
		peak = self._peak,
	}
end

return table.freeze({
	new = Arena.new,
})
