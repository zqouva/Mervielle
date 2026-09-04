--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Merveille = require(ReplicatedStorage.Packages.Merveille)
local PlayerReliquary = require(ReplicatedStorage.Packages.Merveille.Examples.PlayerProfile)

local Projection = Merveille.miroirProjection(PlayerReliquary)

local maybePacket = Merveille.none()
local MirrorRemote = ReplicatedStorage:WaitForChild("PlayerMirror")

MirrorRemote.OnClientEvent:Connect(function(packet: buffer)
	maybePacket = Merveille.some(packet)

	maybePacket:match(function(value)
		local ok, kind = Projection:apply(value)
		local result = if ok then Merveille.ok(kind) else Merveille.err(kind)
		result:match(function(appliedKind)
			local state = Projection:project()
			print(appliedKind, state.Lumen, state.Title, state.Aura.Clarity)
		end, function(reason)
			warn("projection rejected packet", reason)
		end)
	end)
end)
