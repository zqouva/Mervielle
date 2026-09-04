--!strict

local Merveille = require(script.Parent.Parent)
local Wake = require(script.Parent.Parent.Core.Wake)
local PlayerReliquary = require(script.Parent.Parent.Examples.PlayerProfile)

local function expect(condition: boolean, message: string)
	assert(condition, `[Merveille/Validation] {message}`)
end

local function copyBuffer(source: buffer): buffer
	local out = buffer.create(buffer.len(source))
	if buffer.copy ~= nil then
		buffer.copy(out, 0, source, 0, buffer.len(source))
	else
		for index = 0, buffer.len(source) - 1 do
			buffer.writeu8(out, index, buffer.readu8(source, index))
		end
	end
	return out
end

local fakeStore = {
	Schema = PlayerReliquary,
	_saveWake = function()
		return true
	end,
}

expect(
	Merveille.sha256hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
	"sha256 hex mismatch"
)

local body = Wake.newBuffer(PlayerReliquary)
Wake.applyDefaults(PlayerReliquary, body)
Wake.seal(body, PlayerReliquary, {
	active = true,
	sealed = false,
	sealVersion = 0,
	revision = 0,
	commit = 0,
	lockEpoch = 1,
	openUnix = os.time(),
	lastSaveUnix = os.time(),
	ownerPlaceId = 1,
	ownerJobId = "Validation",
	mirrorRevision = 0,
})

local veille = Wake.fromBuffer(fakeStore, "ValidationKey", nil, body, true, false)
local Projection = Merveille.projection(PlayerReliquary)
local FullView = Merveille.view(PlayerReliquary, {
	"Lumen",
	"Title",
	"Aura.Clarity",
	"Marks",
	"Memory",
})

veille:write("Lumen", 100)
veille:write("Title", "phase4")
veille:write("Aura.Clarity", 9.5)
veille:toggle("Marks.Founder", true)
veille:writeBlob("Memory", "cipher")

local blob = veille:blob("Memory")
expect(buffer.readu8(blob, 0) == string.byte("c"), "blob write mismatch")

local keyframe, keyframeLength = veille:keyframe()
expect(keyframe ~= nil and keyframeLength > 0, "keyframe should exist")
local okKeyframe, kindKeyframe = Projection:apply(keyframe :: buffer, keyframeLength)
expect(okKeyframe, `projection rejected keyframe: {kindKeyframe}`)
expect(Projection:read("Lumen") == 100, "keyframe lumen mismatch")
expect(Projection:read("Aura.Clarity") == 9.5, "keyframe clarity mismatch")

veille:add("Lumen", 25)
veille:write("Title", "delta")
local delta, deltaLength = veille:mirror()
expect(delta ~= nil and deltaLength > 0, "delta should exist")
local okDelta, kindDelta = Projection:apply(delta :: buffer, deltaLength)
expect(okDelta, `projection rejected delta: {kindDelta}`)
expect(Projection:read("Lumen") == 125, "delta lumen mismatch")
expect(Projection:read("Title") == "delta", "delta title mismatch")

veille:add("Lumen", 5)
veille:write("Aura.Clarity", 12.25)
local xorPacket, xorLength = veille:xor()
expect(xorPacket ~= nil and xorLength > 0, "xor packet should exist")
local okXor, kindXor = Projection:apply(xorPacket :: buffer, xorLength)
expect(okXor, `projection rejected xor: {kindXor}`)
expect(Projection:read("Lumen") == 130, "xor lumen mismatch")
expect(Projection:read("Aura.Clarity") == 12.25, "xor clarity mismatch")

local staleOk, staleReason = Projection:apply(xorPacket :: buffer, xorLength)
expect(staleOk == false, "stale xor should be rejected")
expect(staleReason == "base revision mismatch", "stale xor rejection reason mismatch")

local snapshot = FullView:project(veille)
expect(snapshot.Lumen == 130, "view lumen mismatch")
expect(snapshot.Title == "delta", "view title mismatch")
expect(snapshot.Aura.Clarity == 12.25, "view clarity mismatch")
expect(snapshot.Marks.Founder == true, "view bit mismatch")
expect(buffer.readu8(snapshot.Memory, 0) == string.byte("c"), "view blob mismatch")

local rawOffset = veille:offset("Lumen")
expect(veille:rawU32(rawOffset) == 130, "raw u32 read mismatch")
veille:writeU32(rawOffset, 222)
expect(veille.Lumen == 222, "raw u32 write mismatch")
local copied = veille:rawBytes(rawOffset, 4)
expect(buffer.readu32(copied, 0) == 222, "raw bytes mismatch")

local key = Merveille.vaultKey("validation-key")
local sealedRecord = copyBuffer(body)
Wake.seal(sealedRecord, PlayerReliquary, {
	active = true,
	sealed = true,
	sealVersion = 2,
	revision = 0,
	commit = 0,
	lockEpoch = 1,
	openUnix = os.time(),
	lastSaveUnix = os.time(),
	ownerPlaceId = 1,
	ownerJobId = "Validation",
	mirrorRevision = 0,
})
Merveille.sealRecord(sealedRecord, key, "validation-nonce")
local sealedHeader = Wake.readHeader(sealedRecord)
expect(sealedHeader.sealed == true, "sealed flag missing")
expect(sealedHeader.sealVersion == 2, "seal version mismatch")
local sealedOk, sealedReason = Merveille.openRecord(sealedRecord, key)
expect(sealedOk, `openRecord failed: {tostring(sealedReason)}`)
local unsealedOk, unsealedReason = Wake.verifyIntegrity(sealedRecord, PlayerReliquary)
expect(unsealedOk, `opened payload failed integrity: {tostring(unsealedReason)}`)

local tampered = copyBuffer(sealedRecord)
Merveille.sealRecord(tampered, key, "validation-nonce-2")
buffer.writeu8(
	tampered,
	PlayerReliquary.HeaderBytes,
	bit32.bxor(buffer.readu8(tampered, PlayerReliquary.HeaderBytes), 0x01)
)
local tamperOk, tamperReason = Merveille.openRecord(tampered, key)
expect(tamperOk == false, "tampered record should fail")
expect(tamperReason == "mac mismatch", "tampered record reason mismatch")

local Observatory = Merveille.observatory(PlayerReliquary)
local html = Observatory:html(veille)
local dirtyHtml = Observatory:dirtyHtml(veille)
local dirtySvg = Observatory:svgDirtySpans(veille)
expect(string.find(html, "<svg", 1, true) ~= nil, "observatory html missing svg")
expect(string.find(dirtyHtml, "Merveille Dirty Report", 1, true) ~= nil, "dirty html missing title")
expect(string.find(dirtySvg, "dirty spans", 1, true) ~= nil, "dirty svg missing label")

local maybeTitle = Merveille.option(Projection:read("Title"))
expect(maybeTitle:unwrap() == "delta", "option unwrap mismatch")

local wakeSave = veille:trySave()
expect(wakeSave:isOk(), "wake trySave should be ok")

local maybePacket = veille:tryMiroir()
expect(maybePacket:isOk(), "wake tryMiroir should be ok")

local result = if staleOk then Merveille.ok("unexpected") else Merveille.err(staleReason)
expect(result:isErr(), "result should be err")
expect(result:unwrapErr() == "base revision mismatch", "result err mismatch")

print("[Merveille/Validation] packet, projection, authenticated vault, raw lanes, view, observatory checks passed")
