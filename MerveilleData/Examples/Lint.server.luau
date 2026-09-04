--!strict

local ServerStorage = game:GetService("ServerStorage")

local Merveille = require(ServerStorage.Packages.Merveille)

local StrictReport = Merveille.strict({
	id = "StrictProfile",
	version = 1,
	pages = 1,
	traits = {
		Lumen = Merveille.u32,
		Title = Merveille.text(48),
		Marks = Merveille.bits({ Founder = 0, Witness = 1 }),
	},
	defaults = {
		Lumen = 0,
		Title = "",
		Marks = { Founder = false, Witness = false },
	},
	miroir = { "Lumen", "Title" },
})

print(StrictReport:text())

local CreativeReport = Merveille.creative({
	id = "CreativeProfile",
	version = 1,
	pages = 1,
	traits = {
		["stage-name"] = Merveille.text(48),
		["mirror light"] = Merveille.text(32),
	},
	defaults = {
		["stage-name"] = "",
		["mirror light"] = "",
	},
	miroir = { "stage-name" },
})

print(CreativeReport:text())

local PerformanceReport = Merveille.performance({
	id = "PerfProfile",
	version = 1,
	pages = 2,
	traits = {
		Lumen = Merveille.u32,
		Memory = Merveille.blob(1024),
		Journal = Merveille.text(512),
	},
	defaults = {
		Lumen = 0,
		Memory = "",
		Journal = "",
	},
	miroir = { "Lumen", "Memory", "Journal" },
})

print(PerformanceReport:text())
