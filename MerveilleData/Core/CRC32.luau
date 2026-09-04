--!strict

local CRC32 = {}

local TABLE = table.create(256)
for i = 0, 255 do
	local crc = i
	for _ = 1, 8 do
		if bit32.band(crc, 1) ~= 0 then
			crc = bit32.bxor(bit32.rshift(crc, 1), 0xEDB88320)
		else
			crc = bit32.rshift(crc, 1)
		end
	end
	TABLE[i + 1] = crc
end

function CRC32.compute(source: buffer, offset: number, length: number): number
	local crc = 0xFFFFFFFF
	for index = 0, length - 1 do
		local byte = buffer.readu8(source, offset + index)
		local lookup = bit32.band(bit32.bxor(crc, byte), 0xFF)
		crc = bit32.bxor(bit32.rshift(crc, 8), TABLE[lookup + 1])
	end
	return bit32.bxor(crc, 0xFFFFFFFF)
end

return table.freeze(CRC32)
