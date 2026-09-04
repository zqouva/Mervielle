--!strict

local Merveille = require(script.Parent.Parent)

return Merveille.reliquary({
	id = "PlayerReliquary",
	version = 1,
	pages = 4,

	traits = {
		Lumen = Merveille.u32,
		Rank = Merveille.u16,
		Title = Merveille.text(48),
		Murmur = Merveille.text(96),
		Aura = Merveille.group({
			Grace = Merveille.f32,
			Poise = Merveille.f32,
			Clarity = Merveille.f32,
		}),
		Rosary = Merveille.rosary(Merveille.u32, 128),
		Marks = Merveille.bits({
			Founder = 0,
			Beta = 1,
			Witness = 2,
		}),
		Memory = Merveille.blob(128),
	},

	defaults = {
		Lumen = 0,
		Rank = 1,
		Title = "",
		Murmur = "",
		Aura = {
			Grace = 0,
			Poise = 0,
			Clarity = 0,
		},
		Rosary = {},
		Marks = {
			Founder = false,
			Beta = false,
			Witness = false,
		},
	},

	miroir = {
		"Lumen",
		"Rank",
		"Title",
		"Aura.Grace",
		"Aura.Poise",
		"Aura.Clarity",
		"Marks",
	},
})
