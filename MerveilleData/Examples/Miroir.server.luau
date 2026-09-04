--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Merveille = require(ServerStorage.Packages.Merveille)
local PlayerReliquary = require(ServerStorage.Packages.Merveille.Examples.PlayerProfile)

local Atelier = Merveille.atelier("Players", PlayerReliquary)
local MirrorRemote = ReplicatedStorage:WaitForChild("PlayerMirror")
local Veilles = {}

local function sendKeyframe(player: Player, veille: any)
	local packet, length = veille:keyframe()
	if packet and length > 0 then
		MirrorRemote:FireClient(player, packet)
	end
end

local function sendUnreliable(player: Player, veille: any)
	local packet, length = veille:miroirUnreliable(1.25)
	if packet and length > 0 then
		MirrorRemote:FireClient(player, packet)
	end
end

Players.PlayerAdded:Connect(function(player)
	local veille = Atelier:veille(player)
	if not veille then
		player:Kick("Merveille could not open your reliquary.")
		return
	end

	Veilles[player] = veille
	sendKeyframe(player, veille)
end)

Players.PlayerRemoving:Connect(function(player)
	local veille = Veilles[player]
	if veille ~= nil then
		veille:close("Manual")
		Veilles[player] = nil
	end
end)

task.spawn(function()
	while true do
		task.wait(0.1)
		for player, veille in Veilles do
			if veille:active() then
				sendUnreliable(player, veille)
			end
		end
	end
end)
