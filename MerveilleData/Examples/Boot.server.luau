--!strict

local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

local Merveille = require(ServerStorage.Packages.Merveille)
local PlayerReliquary = require(ServerStorage.Packages.Merveille.Examples.PlayerProfile)

local Atelier = Merveille.atelier("Players", PlayerReliquary, {
	autosave = 180,
})

local Veilles = {}

Players.PlayerAdded:Connect(function(player)
	local veille = Atelier:veille(player)
	if not veille then
		player:Kick("Merveille could not open your reliquary.")
		return
	end

	Veilles[player] = veille

	veille.Lumen += 100
	veille.Title = "Merveille"
	veille.Marks.Founder = true

	if not veille.Rosary:empty() then
		local last = veille.Rosary:last()
		if last ~= nil then
			print("last bead", last)
		end
	end

	veille.Rosary:push(9001)
end)

Players.PlayerRemoving:Connect(function(player)
	local veille = Veilles[player]
	if veille ~= nil then
		veille:close("Manual")
		Veilles[player] = nil
	end
end)
