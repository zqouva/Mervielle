--!strict

local Hash = {}

local FNV_OFFSET = 2166136261
local FNV_PRIME = 16777619

function Hash.fnv1a32(value: string): number
	local hash = FNV_OFFSET
	for index = 1, #value do
		hash = bit32.bxor(hash, string.byte(value, index))
		hash = (hash * FNV_PRIME) % 4294967296
	end
	return hash
end

return table.freeze(Hash)
