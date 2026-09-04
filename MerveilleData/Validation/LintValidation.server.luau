--!strict

local Merveille = require(script.Parent.Parent)

local function expect(condition: boolean, message: string)
	assert(condition, `[Merveille/Validation] {message}`)
end

local strictReport = Merveille.strict({
	id = "StrictProfile",
	version = 1,
	pages = 1,
	traits = {
		Lumen = Merveille.u32,
		Title = Merveille.text(48),
		Aura = Merveille.group({
			Clarity = Merveille.f32,
		}),
	},
	defaults = {
		Lumen = 0,
		Title = "",
		Aura = {
			Clarity = 0,
		},
	},
	miroir = { "Lumen", "Title", "Aura.Clarity" },
})
expect(strictReport:isOk(), "strict report should pass")

local strictFailure = Merveille.strict({
	id = "StrictFailure",
	version = 1,
	pages = 1,
	traits = {
		["bad-name"] = Merveille.u32,
	},
	defaults = {
		["bad-name"] = 0,
	},
	miroir = { "bad-name" },
})
expect(strictFailure:isOk() == false, "strict should reject unsafe property names")

local creativeReport = Merveille.creative({
	id = "CreativeProfile",
	version = 1,
	pages = 1,
	traits = {
		["bad-name"] = Merveille.u32,
	},
	defaults = {
		["bad-name"] = 0,
	},
	miroir = { "bad-name" },
})
expect(creativeReport:isOk(), "creative mode should allow unsafe style choices when structure is valid")

local performanceReport = Merveille.performance({
	id = "PerformanceProfile",
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
expect(#performanceReport.Warnings > 0 or #performanceReport.Notes > 0, "performance mode should surface cost notes")
expect(string.find(performanceReport:text(), "mirrorBytes", 1, true) ~= nil, "performance text should include metrics")

local defaultFailure = Merveille.strict({
	id = "DefaultFailure",
	version = 1,
	pages = 1,
	traits = {
		Count = Merveille.u16,
		Marks = Merveille.bits({ Founder = 0, Witness = 1 }),
		Rosary = Merveille.rosary(Merveille.u16, 4),
	},
	defaults = {
		Count = 70000,
		Marks = { Founder = "yes" },
		Rosary = { [1] = 1, [3] = 3 },
	},
	miroir = { "Count" },
})
expect(defaultFailure:isOk() == false, "strict should reject corrupted default shapes")

local migrationFailure = Merveille.strict({
	id = "MigrationFailure",
	version = 3,
	pages = 1,
	traits = {
		Lumen = Merveille.u32,
	},
	defaults = {
		Lumen = 0,
	},
	migrations = {
		[1] = true,
		[3] = function() end,
	},
	miroir = { "Lumen" },
})
expect(migrationFailure:isOk() == false, "strict should reject invalid migration shapes")

local ceilingFailure = Merveille.performance({
	id = "CeilingFailure",
	version = 1,
	pages = 2,
	traits = {
		Lumen = Merveille.u32,
		Title = Merveille.text(96),
		Memory = Merveille.blob(256),
	},
	defaults = {
		Lumen = 0,
		Title = "",
		Memory = "",
	},
	miroir = { "Lumen", "Title", "Memory" },
}, {
	mirrorBytesMax = 64,
	textBytesMax = 48,
	blobBytesMax = 128,
})
expect(ceilingFailure:isOk() == false, "performance ceilings should be enforceable")

local creativeCeiling = Merveille.creative({
	id = "CreativeCeiling",
	version = 1,
	pages = 1,
	traits = {
		Title = Merveille.text(96),
	},
	defaults = {
		Title = "",
	},
	miroir = { "Title" },
}, {
	textBytesMax = 32,
})
expect(#creativeCeiling.Warnings > 0, "creative ceilings should warn instead of fail")

print("[Merveille/Validation] lint strict, creative, performance, defaults, migrations, and ceilings checks passed")
