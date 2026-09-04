--!strict

local Merveille = require(script.Parent.Parent)
local PlayerReliquary = require(script.Parent.Parent.Examples.PlayerProfile)

local function expect(condition: boolean, message: string)
	assert(condition, `[Merveille/Validation] {message}`)
end

local Atelier = Merveille.atelier("ProfilerValidation", PlayerReliquary, {
	mock = true,
	profile = true,
	vaultKey = Merveille.vaultKey("profiler-secret"),
	vaultSlots = 2,
})

local veille = Atelier:veille("profile-key")
expect(veille ~= nil, "wake should open")(veille :: any)
	:add("Lumen", 100)(veille :: any)
	:write("Title", "profile")(veille :: any)
	:toggle("Marks.Founder", true)(veille :: any).Rosary
	:push(7)(veille :: any)
	:writeBlob("Memory", "abcdef")
local keyframe, keyframeLength = (veille :: any):keyframe()
expect(keyframe ~= nil and keyframeLength > 0, "keyframe should exist")(veille :: any):add("Lumen", 10)
local delta, deltaLength = (veille :: any):mirror()
expect(delta ~= nil and deltaLength > 0, "delta should exist")(veille :: any):add("Lumen", 5)
local xorPacket, xorLength = (veille :: any):xor()
expect(xorPacket ~= nil and xorLength > 0, "xor packet should exist")
expect((veille :: any):save(), "save should succeed")

local wakeProfiler = Merveille.profiler(veille)
local wakeSnapshot = wakeProfiler:snapshot()
expect(wakeSnapshot.Enabled == true, "wake profiler should be enabled")
expect(wakeSnapshot.PathWrites > 0, "wake path writes should be counted")
expect(wakeSnapshot.BlobWrites > 0, "wake blob writes should be counted")
expect(wakeSnapshot.Keyframes > 0, "wake keyframes should be counted")
expect(wakeSnapshot.Deltas > 0, "wake deltas should be counted")
expect(wakeSnapshot.Xors > 0, "wake xors should be counted")
expect(wakeSnapshot.Saves.count > 0, "wake saves should be counted")
expect(string.find(wakeProfiler:text(), "wake profiler", 1, true) ~= nil, "wake profiler text missing header")
expect(string.find(wakeProfiler:html(), "Merveille Profiler", 1, true) ~= nil, "wake profiler html missing title")

local storeProfiler = Merveille.profiler(Atelier)
local storeSnapshot = storeProfiler:snapshot()
expect(storeSnapshot.Enabled == true, "store profiler should be enabled")
expect(storeSnapshot.Opens.count > 0, "store opens should be counted")
expect(storeSnapshot.Saves.count > 0, "store saves should be counted")
expect(storeSnapshot.UpdateAsync.count > 0, "store updateAsync should be counted")
expect(storeSnapshot.EncodedBytes > 0, "store encoded bytes should be counted")
expect(storeSnapshot.DecodedBytes >= 0, "store decoded bytes should be present")
expect(string.find(storeProfiler:text(), "store profiler", 1, true) ~= nil, "store profiler text missing header")

expect((veille :: any):close("ProfilerValidation"), "close should succeed")

print("[Merveille/Validation] runtime profiler checks passed")
