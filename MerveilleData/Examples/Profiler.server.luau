--!strict

local ServerStorage = game:GetService("ServerStorage")

local Merveille = require(ServerStorage.Packages.Merveille)
local PlayerReliquary = require(ServerStorage.Packages.Merveille.Examples.PlayerProfile)

local Atelier = Merveille.atelier("ProfilerExample", PlayerReliquary, {
	mock = true,
	profile = true,
	vaultKey = Merveille.vaultKey("replace-this-with-your-own-secret"),
})

local veille = Atelier:veille("123456")
if not veille then
	warn("could not open wake")
	return
end

veille:add("Lumen", 100)
veille:write("Title", "profiler")
veille:toggle("Marks.Founder", true)
veille:writeBlob("Memory", "tracked")
veille:keyframe()
veille:add("Lumen", 25)
veille:mirror()
veille:add("Lumen", 5)
veille:xor()
veille:save()

print(Merveille.profiler(veille):text())
print(Merveille.profiler(Atelier):text())
