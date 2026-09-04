--!strict
--[[
	--> ["Merveille : v.0.1.0 : the beginning..."]
	made by Makel/Savi(@sacredludt or @.makel)

	--> ["paradigm"]
	Merveille is an entirely independent data paradigm inside Roblox Studio.
	this is the first version of it. a data system.
	it shouldnt just be a tool, it should literally help you in every way.
	it is not a framework or a standard library.

	--> ["origin"]
	player data storage.
	deep respect for ProfileStore.
	its creator is a mastermind.
	i felt as if i could do more than just store data, i could create a whole new way of thinking about data itself. 

	--> ["code"]
	code is a reflection of how we as humans operate.
	merveille made me cry and i will admit it with pride.

	--> ["identity"]
	i am confident.
	i am loving.
	i do not want.
	i understand.
	i speak it into existance.
	i create.
	i do not speak on what it FEELS like.
	I AM WHAT IT IS.
	AND I AM WHAT IT WILL BE.
	I AM THE SOUL THAT MERVEILLE IS.
	MERVEILLE IS ME.

	--> ["this is...merveille"]
	please use this paradigm with care and respect. 
]]

local Compiler = require(script.Core.Compiler)
local Store = require(script.Core.Store)
local Lint = require(script.Core.Lint)
local Signal = require(script.Core.Signal)
local Hash = require(script.Core.Hash)
local CRC32 = require(script.Core.CRC32)
local SHA256 = require(script.Core.SHA256)
local Codec = require(script.Core.Codec)
local Xor = require(script.Core.Xor)
local Projection = require(script.Core.Projection)
local View = require(script.Core.View)
local Observatory = require(script.Core.Observatory)
local Profiler = require(script.Core.Profiler)
local Arena = require(script.Core.Arena)
local Option = require(script.Core.Option)
local Result = require(script.Core.Result)
local Vault = require(script.Core.Vault)

local Merveille = {}

Merveille.PAGE_SIZE = 0x1000

local function scalar(kind: string)
	return table.freeze({
		__m_kind = "scalar",
		scalar = kind,
	})
end

--> ["numbers"]
Merveille.u8 = scalar("u8")
Merveille.u16 = scalar("u16")
Merveille.u32 = scalar("u32")
Merveille.i8 = scalar("i8")
Merveille.i16 = scalar("i16")
Merveille.i32 = scalar("i32")
Merveille.f32 = scalar("f32")
Merveille.bool = scalar("bool")

Merveille.byte = Merveille.u8
Merveille.word = Merveille.u16
Merveille.dword = Merveille.u32
Merveille.sbyte = Merveille.i8
Merveille.short = Merveille.i16
Merveille.int = Merveille.i32
Merveille.float = Merveille.f32
Merveille.flag = Merveille.bool

--> ["forms"]
function Merveille.text(maxBytes: number)
	assert(
		type(maxBytes) == "number" and maxBytes % 1 == 0 and maxBytes > 0,
		"[Merveille] text(maxBytes) expects a positive integer"
	)
	return table.freeze({
		__m_kind = "text",
		maxBytes = maxBytes,
	})
end

function Merveille.group(traits: { [string]: any })
	assert(type(traits) == "table", "[Merveille] group(traits) expects a table")
	return table.freeze({
		__m_kind = "group",
		fields = traits,
	})
end

function Merveille.rosary(element: any, count: number)
	assert(
		type(element) == "table" and element.__m_kind == "scalar",
		"[Merveille] rosary(element, count) currently expects a scalar element descriptor"
	)
	assert(
		type(count) == "number" and count % 1 == 0 and count > 0,
		"[Merveille] rosary count must be a positive integer"
	)
	return table.freeze({
		__m_kind = "vec",
		element = element,
		capacity = count,
	})
end

function Merveille.bits(mapOrCount: any)
	if type(mapOrCount) == "number" then
		assert(mapOrCount % 1 == 0 and mapOrCount > 0, "[Merveille] bits(count) expects a positive integer")
		return table.freeze({
			__m_kind = "bits",
			count = mapOrCount,
			map = {},
		})
	end

	assert(type(mapOrCount) == "table", "[Merveille] bits(map) expects a trait map or count")
	local count = 0
	for _, position in mapOrCount do
		if position + 1 > count then
			count = position + 1
		end
	end
	return table.freeze({
		__m_kind = "bits",
		count = count,
		map = mapOrCount,
	})
end

function Merveille.blob(bytes: number)
	assert(
		type(bytes) == "number" and bytes % 1 == 0 and bytes > 0,
		"[Merveille] blob(bytes) expects a positive integer"
	)
	return table.freeze({
		__m_kind = "blob",
		bytes = bytes,
	})
end

--> ["aliases"]
Merveille.scripture = Merveille.text
Merveille.chamber = Merveille.group
Merveille.array = Merveille.rosary
Merveille.stigmata = Merveille.bits
Merveille.velvet = Merveille.blob

--> ["libraries"]
Merveille.signal = Signal.new
Merveille.lint = Lint.analyze
Merveille.strict = Lint.strict
Merveille.creative = Lint.creative
Merveille.performance = Lint.performance
Merveille.hash32 = Hash.fnv1a32
Merveille.crc32 = CRC32.compute
Merveille.sha256 = SHA256.compute
Merveille.sha256hex = SHA256.hex
Merveille.encode = Codec.encode
Merveille.decode = Codec.decode
Merveille.xor = Xor.span
Merveille.xorInto = Xor.apply
Merveille.xorMeasure = Xor.measure
Merveille.projection = Projection.new
Merveille.miroirProjection = Projection.new
Merveille.view = View.new
Merveille.observatory = Observatory.new
Merveille.profiler = Profiler.new
Merveille.performanceProfile = Profiler.new
Merveille.arena = Arena.new
Merveille.some = Option.some
Merveille.none = Option.none
Merveille.option = Option.from
Merveille.ok = Result.ok
Merveille.err = Result.err
Merveille.vaultKey = Vault.key
Merveille.sealBody = Vault.sealBody
Merveille.openBody = Vault.openBody
Merveille.sealRecord = Vault.sealRecord
Merveille.openRecord = Vault.openRecord
Merveille.secureEqual = Vault.constantTimeEqual

--> ["paradigm"]
function Merveille.reliquary(definition: { [string]: any }, options: { [string]: any }?)
	if options ~= nil then
		local lintMode = if options.strict == true
			then "strict"
			elseif options.performance == true then "performance"
			elseif type(options.lint) == "string" then options.lint
			else nil
		if lintMode ~= nil then
			local lintOptions = if type(options.lintOptions) == "table" then table.clone(options.lintOptions) else {}
			lintOptions.mode = lintMode
			local report = Lint.analyze(definition, lintOptions)
			assert(report:isOk(), "[Merveille] reliquary lint failed\n" .. report:text())
		end
	end
	return Compiler.compile(definition)
end

function Merveille.atelier(name: string, reliquary: any, options: { [string]: any }?)
	return Store.new(name, reliquary, options)
end

Merveille.sanctum = Merveille.atelier

return table.freeze(Merveille)
