--!strict

-->	["vault"]
-->	Authenticated record sealing.
-->	The older raw body seal is still exposed for compatibility, but the stronger
-->	layer now seals full records with:
-->	- per-record nonce material
-->	- derived subkeys
-->	- XTEA body encryption
-->	- HMAC-SHA256 authentication over the record with the MAC lane zeroed
-->
-->	That means the store path no longer depends on confidentiality alone.

local Hash = require(script.Parent.Hash)
local SHA256 = require(script.Parent.SHA256)

local Vault = {}

local HEADER_SIZE = 0x0100
local OFF_SEAL_VERSION = 0x0098
local OFF_SEAL_NONCE = 0x009C
local OFF_SEAL_MAC = 0x00AC
local SEAL_VERSION_AUTH = 2
local NONCE_BYTES = 16
local MAC_BYTES = 32
local DELTA = 0x9E3779B9
local ROUNDS = 32
local WORD = 4294967296
local BUFFER_TO_STRING = buffer.tostring
local BUFFER_COPY = buffer.copy

local function u32(value: number): number
	return value % WORD
end

local function writeWordBE(target: buffer, offset: number, value: number)
	buffer.writeu8(target, offset, bit32.band(bit32.rshift(value, 24), 0xFF))
	buffer.writeu8(target, offset + 1, bit32.band(bit32.rshift(value, 16), 0xFF))
	buffer.writeu8(target, offset + 2, bit32.band(bit32.rshift(value, 8), 0xFF))
	buffer.writeu8(target, offset + 3, bit32.band(value, 0xFF))
end

local function readWordBE(source: buffer, offset: number): number
	return bit32.bor(
		bit32.lshift(buffer.readu8(source, offset), 24),
		bit32.lshift(buffer.readu8(source, offset + 1), 16),
		bit32.lshift(buffer.readu8(source, offset + 2), 8),
		buffer.readu8(source, offset + 3)
	)
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

local function zeroBytes(target: buffer, offset: number, count: number)
	for index = 0, count - 1 do
		buffer.writeu8(target, offset + index, 0)
	end
end

local function binaryFrom(source: any, offset: number?, length: number?): string
	if type(source) == "string" then
		local start = if offset == nil then 0 else offset
		if length == nil then
			return string.sub(source, start + 1)
		end
		return string.sub(source, start + 1, start + length)
	end
	assert(typeof(source) == "buffer", "[Merveille/Vault] expected string or buffer")
	local start = if offset == nil then 0 else offset
	local count = if length == nil then buffer.len(source) - start else length
	if start == 0 and count == buffer.len(source) and BUFFER_TO_STRING ~= nil then
		return BUFFER_TO_STRING(source)
	end
	local out = table.create(count)
	for index = 0, count - 1 do
		out[index + 1] = string.char(buffer.readu8(source, start + index))
	end
	return table.concat(out)
end

local function digestString(source: any): string
	return binaryFrom(SHA256.compute(source))
end

local function hmac(keyMaterial: any, message: any): buffer
	local blockSize = 64
	local key = binaryFrom(keyMaterial)
	if #key > blockSize then
		key = digestString(key)
	end
	if #key < blockSize then
		key ..= string.rep("\0", blockSize - #key)
	end

	local inner = table.create(blockSize)
	local outer = table.create(blockSize)
	for index = 1, blockSize do
		local byte = string.byte(key, index)
		inner[index] = string.char(bit32.bxor(byte, 0x36))
		outer[index] = string.char(bit32.bxor(byte, 0x5C))
	end

	local innerDigest = SHA256.compute(table.concat(inner) .. binaryFrom(message))
	return SHA256.compute(table.concat(outer) .. binaryFrom(innerDigest))
end

local function packLegacyWords(words: { number }): { number }
	assert(#words == 4, "[Merveille/Vault] XTEA key needs exactly 4 u32 words")
	return table.freeze({
		u32(words[1]),
		u32(words[2]),
		u32(words[3]),
		u32(words[4]),
	})
end

local function nonceFrom(source: any?): buffer
	local seed = if source == nil then `{os.time()}:{os.clock()}:{math.random(1, 2147483647)}` else source
	local digest = SHA256.compute(seed)
	local nonce = buffer.create(NONCE_BYTES)
	copyBytes(nonce, 0, digest, 0, NONCE_BYTES)
	return nonce
end

local function normalizeKey(source: any)
	if type(source) == "table" and source.__vault == true then
		return source
	end

	local masterDigest: buffer
	if type(source) == "table" then
		local words = packLegacyWords(source)
		local lane = buffer.create(16)
		writeWordBE(lane, 0, words[1])
		writeWordBE(lane, 4, words[2])
		writeWordBE(lane, 8, words[3])
		writeWordBE(lane, 12, words[4])
		masterDigest = SHA256.compute(lane)
	else
		assert(
			type(source) == "string" and source ~= "",
			"[Merveille/Vault] key source must be a non-empty string, key object, or legacy 4-word table"
		)
		masterDigest = SHA256.compute(source)
	end

	return table.freeze({
		__vault = true,
		master = masterDigest,
		legacy = packLegacyWords({
			Hash.fnv1a32(binaryFrom(masterDigest) .. "::legacy0"),
			Hash.fnv1a32(binaryFrom(masterDigest) .. "::legacy1"),
			Hash.fnv1a32(binaryFrom(masterDigest) .. "::legacy2"),
			Hash.fnv1a32(binaryFrom(masterDigest) .. "::legacy3"),
		}),
	})
end

local function deriveEncryptionWords(key: any, nonce: buffer): { number }
	local material = hmac(key.master, "enc:" .. binaryFrom(nonce))
	return table.freeze({
		readWordBE(material, 0),
		readWordBE(material, 4),
		readWordBE(material, 8),
		readWordBE(material, 12),
	})
end

local function deriveMacKey(key: any, nonce: buffer): buffer
	return hmac(key.master, "mac:" .. binaryFrom(nonce))
end

local function encryptBlock(target: buffer, offset: number, keyWords: { number })
	local v0 = buffer.readu32(target, offset)
	local v1 = buffer.readu32(target, offset + 4)
	local sum = 0
	for _ = 1, ROUNDS do
		local mix0 = u32(bit32.bxor(bit32.lshift(v1, 4), bit32.rshift(v1, 5)) + v1)
		v0 = u32(v0 + bit32.bxor(mix0, u32(sum + keyWords[bit32.band(sum, 3) + 1])))
		sum = u32(sum + DELTA)
		local shifted = bit32.rshift(sum, 11)
		local mix1 = u32(bit32.bxor(bit32.lshift(v0, 4), bit32.rshift(v0, 5)) + v0)
		v1 = u32(v1 + bit32.bxor(mix1, u32(sum + keyWords[bit32.band(shifted, 3) + 1])))
	end
	buffer.writeu32(target, offset, v0)
	buffer.writeu32(target, offset + 4, v1)
end

local function decryptBlock(target: buffer, offset: number, keyWords: { number })
	local v0 = buffer.readu32(target, offset)
	local v1 = buffer.readu32(target, offset + 4)
	local sum = u32(DELTA * ROUNDS)
	for _ = 1, ROUNDS do
		local shifted = bit32.rshift(sum, 11)
		local mix1 = u32(bit32.bxor(bit32.lshift(v0, 4), bit32.rshift(v0, 5)) + v0)
		v1 = u32(v1 - bit32.bxor(mix1, u32(sum + keyWords[bit32.band(shifted, 3) + 1])))
		local mix0 = u32(bit32.bxor(bit32.lshift(v1, 4), bit32.rshift(v1, 5)) + v1)
		v0 = u32(v0 - bit32.bxor(mix0, u32(sum + keyWords[bit32.band(sum, 3) + 1])))
		sum = u32(sum - DELTA)
	end
	buffer.writeu32(target, offset, v0)
	buffer.writeu32(target, offset + 4, v1)
end

local function applyBlocks(target: buffer, keyWords: { number }, offset: number, length: number, decrypting: boolean)
	assert(length % 8 == 0, "[Merveille/Vault] sealed length must be divisible by 8")
	for index = 0, length - 8, 8 do
		if decrypting then
			decryptBlock(target, offset + index, keyWords)
		else
			encryptBlock(target, offset + index, keyWords)
		end
	end
end

local function writeMac(target: buffer, digest: buffer)
	copyBytes(target, OFF_SEAL_MAC, digest, 0, MAC_BYTES)
end

local function readMac(target: buffer): buffer
	local digest = buffer.create(MAC_BYTES)
	copyBytes(digest, 0, target, OFF_SEAL_MAC, MAC_BYTES)
	return digest
end

function Vault.key(source: any)
	return normalizeKey(source)
end

function Vault.sealBody(target: buffer, keySource: any, bodyOffset: number?, bodyLength: number?)
	local key = normalizeKey(keySource)
	local offset = if bodyOffset == nil then HEADER_SIZE else bodyOffset
	local length = if bodyLength == nil then buffer.len(target) - offset else bodyLength
	applyBlocks(target, key.legacy, offset, length, false)
	return target
end

function Vault.openBody(target: buffer, keySource: any, bodyOffset: number?, bodyLength: number?)
	local key = normalizeKey(keySource)
	local offset = if bodyOffset == nil then HEADER_SIZE else bodyOffset
	local length = if bodyLength == nil then buffer.len(target) - offset else bodyLength
	applyBlocks(target, key.legacy, offset, length, true)
	return target
end

function Vault.sealRecord(target: buffer, keySource: any, nonceSource: any?)
	local key = normalizeKey(keySource)
	local nonce = nonceFrom(nonceSource)
	buffer.writeu16(target, OFF_SEAL_VERSION, SEAL_VERSION_AUTH)
	copyBytes(target, OFF_SEAL_NONCE, nonce, 0, NONCE_BYTES)
	zeroBytes(target, OFF_SEAL_MAC, MAC_BYTES)

	local encWords = deriveEncryptionWords(key, nonce)
	applyBlocks(target, encWords, HEADER_SIZE, buffer.len(target) - HEADER_SIZE, false)

	local macKey = deriveMacKey(key, nonce)
	local mac = hmac(macKey, target)
	writeMac(target, mac)
	return target
end

function Vault.openRecord(target: buffer, keySource: any): (boolean, string?)
	local key = normalizeKey(keySource)
	local version = buffer.readu16(target, OFF_SEAL_VERSION)
	if version == 0 or version == 1 then
		Vault.openBody(target, key)
		return true, nil
	end
	if version ~= SEAL_VERSION_AUTH then
		return false, `unsupported seal version {version}`
	end

	local nonce = buffer.create(NONCE_BYTES)
	copyBytes(nonce, 0, target, OFF_SEAL_NONCE, NONCE_BYTES)
	local expected = readMac(target)
	zeroBytes(target, OFF_SEAL_MAC, MAC_BYTES)
	local macKey = deriveMacKey(key, nonce)
	local actual = hmac(macKey, target)
	local ok = Vault.constantTimeEqual(expected, actual)
	writeMac(target, expected)
	if not ok then
		return false, "mac mismatch"
	end

	local encWords = deriveEncryptionWords(key, nonce)
	applyBlocks(target, encWords, HEADER_SIZE, buffer.len(target) - HEADER_SIZE, true)
	return true, nil
end

local function bufferByte(source: any, index: number): number
	if type(source) == "string" then
		return string.byte(source, index + 1)
	end
	return buffer.readu8(source, index)
end

local function bufferSize(source: any): number
	if type(source) == "string" then
		return #source
	end
	return buffer.len(source)
end

function Vault.constantTimeEqual(left: any, right: any): boolean
	local leftLength = bufferSize(left)
	local rightLength = bufferSize(right)
	if leftLength ~= rightLength then
		return false
	end
	local diff = 0
	for index = 0, leftLength - 1 do
		diff = bit32.bor(diff, bit32.bxor(bufferByte(left, index), bufferByte(right, index)))
	end
	return diff == 0
end

return table.freeze({
	key = Vault.key,
	sealBody = Vault.sealBody,
	openBody = Vault.openBody,
	sealRecord = Vault.sealRecord,
	openRecord = Vault.openRecord,
	constantTimeEqual = Vault.constantTimeEqual,
})
