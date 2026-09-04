--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Merveille = require(ReplicatedStorage.Packages.Merveille)
local PlayerReliquary = require(ReplicatedStorage.Packages.Merveille.Examples.PlayerProfile)

local Projection = Merveille.projection(PlayerReliquary)
local MirrorRemote = ReplicatedStorage:WaitForChild("PlayerMirror")

MirrorRemote.OnClientEvent:Connect(function(packet: buffer)
	local ok, kind = Projection:apply(packet)
	if not ok then
		warn("projection rejected packet", kind)
		return
	end

	local state = Projection:project()
	print(kind, state.Lumen, state.Rank, state.Title)
	print(state.Aura.Grace, state.Aura.Poise, state.Aura.Clarity)
	print(state.Marks.Founder, state.Marks.Beta, state.Marks.Witness)
end)
