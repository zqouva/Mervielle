--!strict

local ServerStorage = game:GetService("ServerStorage")

local Merveille = require(ServerStorage.Packages.Merveille)
local PlayerReliquary = require(ServerStorage.Packages.Merveille.Examples.PlayerProfile)

local bodyKey = Merveille.vaultKey("replace-this-with-your-own-secret")
local Atelier = Merveille.atelier("Players", PlayerReliquary, {
	autosave = 180,
	vaultKey = bodyKey,
	vaultSlots = 4,
})

local View = Merveille.view(PlayerReliquary, {
	"Lumen",
	"Title",
	"Aura.Clarity",
	"Memory",
})

Atelier:matchVeille("123456", function(veille)
	veille:add("Lumen", 100)
	veille:clamp("Lumen", 0, 999999)
	veille:write("Title", "phase 4")
	veille:toggle("Marks.Founder", true)
	veille:writeBlob("Memory", "sealed")

	local snapshot = View:project(veille)
	print(snapshot.Lumen, snapshot.Title, snapshot.Aura.Clarity)

	veille:matchMiroir(function(packet)
		print("miroir packet", packet.Kind, packet.Length)
	end, function(reason)
		warn("no miroir packet", reason)
	end)

	local Observatory = Merveille.observatory(veille)
	print(Observatory:wake(veille))
	local dirtyHtml = Observatory:dirtyHtml(veille)
	print("dirty html bytes", #dirtyHtml)

	veille:matchSave(function()
		print("saved")
	end, function(reason)
		warn("save failed", reason)
	end)
end, function(reason)
	warn("could not open wake", reason)
end)
