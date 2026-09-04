-->	["lint"]
-->	Data linting for reliquary definitions.
-->	Modes:
-->	- strict: pushes hard on structural certainty and property-safe naming
-->	- creative: keeps structure safe but gives more freedom on style/layout choices
-->	- performance: judges shape, mirror cost, slack, and likely runtime pressure

local Compiler = require(script.Parent.Compiler)

local Lint = {}
local Report = {}
Report.__index = Report

local SUPPORTED_SCALARS = {
	u8 = true,
	u16 = true,
	u32 = true,
	i8 = true,
	i16 = true,
	i32 = true,
	f32 = true,
	bool = true,
}

local SCALAR_LIMITS = {
	u8 = { integer = true, min = 0, max = 255 },
	u16 = { integer = true, min = 0, max = 65535 },
	u32 = { integer = true, min = 0, max = 4294967295 },
	i8 = { integer = true, min = -128, max = 127 },
	i16 = { integer = true, min = -32768, max = 32767 },
	i32 = { integer = true, min = -2147483648, max = 2147483647 },
	f32 = { integer = false },
}

local function push(list: { any }, item: any)
	list[#list + 1] = item
end

local function safeIdentifier(name: string): boolean
	return string.match(name, "^[A-Za-z_][A-Za-z0-9_]*$") ~= nil
end

local function addIssue(report: any, severity: string, code: string, message: string, path: string?)
	local issue = table.freeze({
		severity = severity,
		code = code,
		message = message,
		path = path,
	})
	push(report.Issues, issue)
	if severity == "error" then
		push(report.Errors, issue)
	elseif severity == "warning" then
		push(report.Warnings, issue)
	else
		push(report.Notes, issue)
	end
end

local function grade(
	report: any,
	kind: string,
	strictSeverity: string,
	creativeSeverity: string,
	performanceSeverity: string,
	code: string,
	message: string,
	path: string?
)
	local severity = if report.Mode == "strict"
		then strictSeverity
		elseif report.Mode == "creative" then creativeSeverity
		else performanceSeverity
	if severity == "off" then
		return
	end
	addIssue(report, severity, code, message, path)
end

local function readTraits(definition: { [string]: any }): ({ [string]: any }?, string?)
	local traits = definition.traits or definition.sigils or definition.fields
	if type(traits) ~= "table" then
		return nil, "definition needs a traits table"
	end
	return traits, nil
end

local applyCeiling

local function visitField(report: any, descriptor: any, path: string, depth: number)
	report.DeepestPath = math.max(report.DeepestPath, depth)
	if type(descriptor) ~= "table" then
		addIssue(report, "error", "invalid-descriptor", "field is not a Merveille descriptor table", path)
		return
	end
	local kind = descriptor.__m_kind
	if type(kind) ~= "string" then
		addIssue(report, "error", "missing-kind", "field is missing __m_kind", path)
		return
	end
	if not safeIdentifier(string.match(path, "[^%.]+$") or path) then
		grade(
			report,
			"naming",
			"error",
			"note",
			"warning",
			"unsafe-name",
			"field name does not stay in normal property syntax safely",
			path
		)
	end

	if kind == "scalar" then
		report.KindCounts.scalar += 1
		if SUPPORTED_SCALARS[descriptor.scalar] ~= true then
			addIssue(report, "error", "scalar-kind", `unsupported scalar kind '{tostring(descriptor.scalar)}'`, path)
		end
		return
	elseif kind == "text" then
		report.KindCounts.text += 1
		if type(descriptor.maxBytes) ~= "number" or descriptor.maxBytes % 1 ~= 0 or descriptor.maxBytes <= 0 then
			addIssue(report, "error", "text-bytes", "text(maxBytes) needs a positive integer", path)
		elseif descriptor.maxBytes > 256 then
			grade(
				report,
				"text-size",
				"warning",
				"note",
				"warning",
				"large-text",
				`text lane is large ({descriptor.maxBytes} bytes)`,
				path
			)
		end
		applyCeiling(
			report,
			descriptor.maxBytes,
			report.Options.textBytesMax,
			"text-bytes-ceiling",
			`text lane {descriptor.maxBytes} exceeds ceiling {tostring(report.Options.textBytesMax)}`
		)
		return
	elseif kind == "bits" then
		report.KindCounts.bits += 1
		local count = descriptor.count
		if type(count) ~= "number" or count % 1 ~= 0 or count <= 0 then
			addIssue(report, "error", "bits-count", "bits need a positive integer count", path)
			return
		end
		local map = descriptor.map
		if type(map) == "table" and next(map) ~= nil then
			local seen = {}
			local maxPosition = -1
			for bitName, position in map do
				if type(bitName) ~= "string" then
					addIssue(report, "error", "bit-name", "bit map keys must be strings", path)
				elseif not safeIdentifier(bitName) then
					grade(
						report,
						"bit-naming",
						"error",
						"note",
						"warning",
						"unsafe-bit-name",
						"bit name does not stay in normal property syntax safely",
						`{path}.{bitName}`
					)
				end
				if type(position) ~= "number" or position % 1 ~= 0 or position < 0 then
					addIssue(
						report,
						"error",
						"bit-position",
						"bit positions must be non-negative integers",
						`{path}.{tostring(bitName)}`
					)
				elseif seen[position] then
					addIssue(
						report,
						"error",
						"bit-collision",
						`bit position {position} is used more than once`,
						`{path}.{tostring(bitName)}`
					)
				else
					seen[position] = true
					if position > maxPosition then
						maxPosition = position
					end
				end
			end
			if maxPosition + 1 ~= count then
				grade(
					report,
					"bit-density",
					"warning",
					"note",
					"warning",
					"sparse-bits",
					`bit count {count} does not match the highest mapped bit {maxPosition}`,
					path
				)
			end
		end
		return
	elseif kind == "blob" then
		report.KindCounts.blob += 1
		if type(descriptor.bytes) ~= "number" or descriptor.bytes % 1 ~= 0 or descriptor.bytes <= 0 then
			addIssue(report, "error", "blob-bytes", "blob(bytes) needs a positive integer", path)
		elseif descriptor.bytes > 512 then
			grade(
				report,
				"blob-size",
				"warning",
				"note",
				"warning",
				"large-blob",
				`blob lane is large ({descriptor.bytes} bytes)`,
				path
			)
		end
		applyCeiling(
			report,
			descriptor.bytes,
			report.Options.blobBytesMax,
			"blob-bytes-ceiling",
			`blob lane {descriptor.bytes} exceeds ceiling {tostring(report.Options.blobBytesMax)}`
		)
		return
	elseif kind == "vec" then
		report.KindCounts.vec += 1
		if type(descriptor.element) ~= "table" or descriptor.element.__m_kind ~= "scalar" then
			addIssue(report, "error", "vec-element", "rosary element must be a scalar descriptor", path)
		end
		if type(descriptor.capacity) ~= "number" or descriptor.capacity % 1 ~= 0 or descriptor.capacity <= 0 then
			addIssue(report, "error", "vec-capacity", "rosary capacity must be a positive integer", path)
		elseif descriptor.capacity > 1024 then
			grade(
				report,
				"vec-capacity",
				"warning",
				"note",
				"warning",
				"large-rosary",
				`rosary capacity is large ({descriptor.capacity})`,
				path
			)
		end
		applyCeiling(
			report,
			descriptor.capacity,
			report.Options.vecCapacityMax,
			"vec-capacity-ceiling",
			`rosary capacity {descriptor.capacity} exceeds ceiling {tostring(report.Options.vecCapacityMax)}`
		)
		return
	elseif kind == "group" then
		report.KindCounts.group += 1
		if type(descriptor.fields) ~= "table" then
			addIssue(report, "error", "group-fields", "group needs a fields table", path)
			return
		end
		local hasChild = false
		for childName, childDescriptor in descriptor.fields do
			hasChild = true
			if type(childName) ~= "string" then
				addIssue(report, "error", "group-child-name", "group field names must be strings", path)
			else
				visitField(report, childDescriptor, `{path}.{childName}`, depth + 1)
			end
		end
		if not hasChild then
			grade(report, "empty-group", "warning", "note", "warning", "empty-group", "group has no fields", path)
		end
		return
	end

	addIssue(report, "error", "unknown-kind", `unsupported descriptor kind '{kind}'`, path)
end

local function finiteNumber(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function validateScalarDefault(report: any, scalar: string, value: any, path: string)
	if scalar == "bool" then
		if type(value) ~= "boolean" then
			addIssue(report, "error", "default-bool", "boolean default must be true or false", path)
		end
		return
	end
	if type(value) ~= "number" or not finiteNumber(value) then
		addIssue(report, "error", "default-number", "numeric default must be a finite number", path)
		return
	end
	local limit = SCALAR_LIMITS[scalar]
	if limit ~= nil and limit.integer and value % 1 ~= 0 then
		addIssue(report, "error", "default-integer", `default for {scalar} must be an integer`, path)
		return
	end
	local minValue = if limit ~= nil then limit.min else nil
	local maxValue = if limit ~= nil then limit.max else nil
	if (minValue ~= nil and value < minValue) or (maxValue ~= nil and value > maxValue) then
		addIssue(report, "error", "default-range", `default for {scalar} is out of range`, path)
		return
	end
end

local function validateDefaultValue(report: any, descriptor: any, value: any, path: string)
	if value == nil then
		return
	end
	local kind = descriptor.__m_kind
	if kind == "scalar" then
		validateScalarDefault(report, descriptor.scalar, value, path)
	elseif kind == "text" then
		if type(value) ~= "string" then
			addIssue(report, "error", "default-text", "text default must be a string", path)
		elseif #value > descriptor.maxBytes then
			addIssue(
				report,
				"error",
				"default-text-overflow",
				`text default exceeds lane size {descriptor.maxBytes}`,
				path
			)
		end
	elseif kind == "bits" then
		if type(value) ~= "table" then
			addIssue(report, "error", "default-bits", "bits default must be a table", path)
			return
		end
		for bitName, enabled in value do
			if type(enabled) ~= "boolean" then
				addIssue(
					report,
					"error",
					"default-bit-value",
					"bit defaults must be booleans",
					`{path}.{tostring(bitName)}`
				)
			end
			local position = if type(bitName) == "string"
				then descriptor.map[bitName]
				else if type(bitName) == "number" and bitName % 1 == 0 then bitName - 1 else nil
			if position == nil or position < 0 or position >= descriptor.count then
				addIssue(
					report,
					"error",
					"default-bit-key",
					"bit default references an unknown bit",
					`{path}.{tostring(bitName)}`
				)
			end
		end
	elseif kind == "blob" then
		if type(value) == "string" then
			if #value > descriptor.bytes then
				addIssue(
					report,
					"error",
					"default-blob-overflow",
					`blob default exceeds lane size {descriptor.bytes}`,
					path
				)
			end
		elseif typeof(value) == "buffer" then
			if buffer.len(value) > descriptor.bytes then
				addIssue(
					report,
					"error",
					"default-blob-overflow",
					`blob default exceeds lane size {descriptor.bytes}`,
					path
				)
			end
		else
			addIssue(report, "error", "default-blob", "blob default must be a string or buffer", path)
		end
	elseif kind == "vec" then
		if type(value) ~= "table" then
			addIssue(report, "error", "default-vec", "rosary default must be an array table", path)
			return
		end
		local denseCount = 0
		local numericCount = 0
		local maxIndex = 0
		for key in value do
			if type(key) ~= "number" or key % 1 ~= 0 or key < 1 then
				addIssue(
					report,
					"error",
					"default-vec-key",
					"rosary defaults only accept positive integer indices",
					path
				)
			else
				numericCount += 1
				if key > maxIndex then
					maxIndex = key
				end
			end
		end
		for index, item in ipairs(value) do
			denseCount = index
			if type(descriptor.element) == "table" and type(descriptor.element.scalar) == "string" then
				validateScalarDefault(report, descriptor.element.scalar, item, `{path}[{index}]`)
			end
		end
		if denseCount ~= numericCount or denseCount ~= maxIndex then
			addIssue(report, "error", "default-vec-sparse", "rosary defaults must be dense arrays without holes", path)
		end
		if denseCount > descriptor.capacity then
			addIssue(
				report,
				"error",
				"default-vec-overflow",
				`rosary default exceeds capacity {descriptor.capacity}`,
				path
			)
		end
	elseif kind == "group" then
		if type(value) ~= "table" then
			addIssue(report, "error", "default-group", "group default must be a table", path)
			return
		end
		for childName, childDescriptor in descriptor.fields do
			if value[childName] == nil then
				grade(
					report,
					"group-defaults",
					"warning",
					"off",
					"note",
					"missing-group-default",
					"group default omits a child field",
					`{path}.{childName}`
				)
			else
				validateDefaultValue(report, childDescriptor, value[childName], `{path}.{childName}`)
			end
		end
		for childName in value do
			if descriptor.fields[childName] == nil then
				addIssue(
					report,
					"error",
					"unknown-group-default",
					"group default contains an unknown child field",
					`{path}.{tostring(childName)}`
				)
			end
		end
	end
end

local function visitDefaults(report: any, traits: { [string]: any }, defaults: { [string]: any })
	if type(defaults) ~= "table" then
		addIssue(report, "error", "defaults-type", "defaults must be a table", nil)
		return
	end
	for fieldName, descriptor in traits do
		if type(fieldName) == "string" then
			if defaults[fieldName] == nil then
				grade(
					report,
					"defaults",
					"warning",
					"off",
					"note",
					"missing-default",
					"root field has no explicit default",
					fieldName
				)
			else
				validateDefaultValue(report, descriptor, defaults[fieldName], fieldName)
			end
		end
	end
	for fieldName in defaults do
		if traits[fieldName] == nil then
			grade(
				report,
				"defaults-extra",
				"warning",
				"note",
				"warning",
				"unknown-default",
				"defaults contains a root key not present in traits",
				tostring(fieldName)
			)
		end
	end
end

local function visitMirror(report: any, definition: { [string]: any }, traits: { [string]: any })
	local mirror = definition.miroir or definition.mirror
	if mirror == nil then
		grade(report, "mirror", "warning", "note", "warning", "missing-mirror", "definition has no miroir list", nil)
		return
	end
	if type(mirror) ~= "table" then
		addIssue(report, "error", "mirror-type", "miroir must be an array of paths", nil)
		return
	end
	local seen = {}
	local function resolvePath(path: string): any
		local cursor = traits
		local start = 1
		while true do
			local stop = string.find(path, ".", start, true)
			local part = if stop == nil then string.sub(path, start) else string.sub(path, start, stop - 1)
			local nextNode = cursor[part]
			if nextNode == nil then
				return nil
			end
			if stop == nil then
				return nextNode
			end
			if type(nextNode) ~= "table" or nextNode.__m_kind ~= "group" then
				return nil
			end
			cursor = nextNode.fields
			start = stop + 1
		end
	end
	for index, path in ipairs(mirror) do
		if type(path) ~= "string" or path == "" then
			addIssue(report, "error", "mirror-path", `miroir[{index}] must be a non-empty string path`, nil)
		else
			local resolved = resolvePath(path)
			if seen[path] then
				grade(
					report,
					"mirror-duplicate",
					"error",
					"warning",
					"warning",
					"duplicate-mirror",
					"miroir repeats the same path more than once",
					path
				)
			else
				seen[path] = true
			end
			if resolved == nil then
				addIssue(report, "error", "mirror-missing", "miroir path does not exist in traits", path)
			elseif type(resolved) == "table" and resolved.__m_kind == "group" then
				addIssue(report, "error", "mirror-group", "miroir path cannot point at a group directly", path)
			end
		end
	end
end

local function visitMigrations(report: any, migrations: any, currentVersion: number)
	if migrations == nil then
		if currentVersion > 1 then
			grade(
				report,
				"migrations",
				"warning",
				"note",
				"warning",
				"missing-migrations",
				"definition version is above 1 but no migrations table is present",
				nil
			)
		end
		return
	end
	if type(migrations) ~= "table" then
		addIssue(report, "error", "migrations-type", "migrations must be a table", nil)
		return
	end
	local seen = {}
	local versions = {}
	for version, step in migrations do
		if type(version) ~= "number" or version % 1 ~= 0 or version <= 0 then
			addIssue(
				report,
				"error",
				"migration-key",
				"migration keys must be positive integer source versions",
				tostring(version)
			)
		else
			seen[version] = true
			versions[#versions + 1] = version
			if version >= currentVersion then
				grade(
					report,
					"migration-range",
					"warning",
					"note",
					"warning",
					"future-migration",
					"migration key is not below the current schema version",
					tostring(version)
				)
			end
		end
		if type(step) ~= "function" then
			if type(step) == "table" then
				if type(step.up) ~= "function" then
					addIssue(
						report,
						"error",
						"migration-shape",
						"migration table entries need an up function",
						tostring(version)
					)
				end
			else
				addIssue(
					report,
					"error",
					"migration-shape",
					"migration entries must be a function or a table with up",
					tostring(version)
				)
			end
		end
	end
	if #versions == 0 then
		if currentVersion > 1 then
			grade(
				report,
				"migrations",
				"warning",
				"note",
				"warning",
				"empty-migrations",
				"definition version is above 1 but migrations is empty",
				nil
			)
		end
		return
	end
	table.sort(versions)
	for version = 1, currentVersion - 1 do
		if seen[version] ~= true then
			grade(
				report,
				"migration-gaps",
				"warning",
				"note",
				"warning",
				"missing-migration-step",
				`no migration step is declared for source version {version}`,
				tostring(version)
			)
		end
	end
end

applyCeiling = function(report: any, value: number, limit: number?, code: string, message: string)
	if limit == nil then
		return
	end
	if value > limit then
		addIssue(report, if report.Mode == "creative" then "warning" else "error", code, message, nil)
	end
end

function Report:isOk(): boolean
	return #self.Errors == 0
end

function Report:text(): string
	local lines = {}
	push(lines, `--> ["lint"] mode={self.Mode} ok={tostring(self:isOk())}`)
	if self.Schema ~= nil then
		push(lines, `schema={self.Schema.Id} version={self.Schema.Version} pages={self.Schema.Pages}`)
		push(
			lines,
			`layoutBytes={self.Schema.LayoutEnd} pageBytes={self.Schema.PageBytes} mirrorBytes={self.Schema.MirrorSize}`
		)
		push(
			lines,
			`payloadBytes={self.Schema.PayloadBytes or 0} alignmentWaste={self.Schema.AlignmentWaste or 0} slackBytes={self.Schema.SlackBytes or 0}`
		)
	end
	push(lines, `errors={#self.Errors} warnings={#self.Warnings} notes={#self.Notes}`)
	push(
		lines,
		`kinds scalar={self.KindCounts.scalar} text={self.KindCounts.text} bits={self.KindCounts.bits} blob={self.KindCounts.blob} vec={self.KindCounts.vec} group={self.KindCounts.group} depth={self.DeepestPath}`
	)
	for _, issue in ipairs(self.Issues) do
		local where = if issue.path ~= nil then string.format(" @ %s", issue.path) else ""
		push(lines, string.format("[%s] %s%s :: %s", issue.severity, issue.code, where, issue.message))
	end
	return table.concat(lines, "\n")
end

function Lint.analyze(definition: { [string]: any }, options: { [string]: any }?)
	local opts = if type(options) == "table" then options else {}
	local mode = if type(opts.mode) == "string" then opts.mode else "strict"
	assert(
		mode == "strict" or mode == "creative" or mode == "performance",
		`[Merveille/Lint] unknown mode '{tostring(mode)}'`
	)

	local report = setmetatable({
		Mode = mode,
		Options = opts,
		Issues = {},
		Errors = {},
		Warnings = {},
		Notes = {},
		KindCounts = {
			scalar = 0,
			text = 0,
			bits = 0,
			blob = 0,
			vec = 0,
			group = 0,
		},
		DeepestPath = 1,
		Schema = nil,
	}, Report)

	if type(definition) ~= "table" then
		addIssue(report, "error", "definition-type", "reliquary definition must be a table", nil)
		return report
	end

	if definition.sigils ~= nil then
		grade(
			report,
			"aliases",
			"warning",
			"note",
			"note",
			"alias-sigils",
			"sigils alias is supported but traits is cleaner",
			nil
		)
	end
	if definition.fields ~= nil then
		grade(
			report,
			"aliases",
			"warning",
			"note",
			"note",
			"alias-fields",
			"fields alias is supported but traits is cleaner",
			nil
		)
	end
	if definition.defauts ~= nil then
		grade(
			report,
			"aliases",
			"warning",
			"note",
			"note",
			"alias-defauts",
			"defauts alias is supported but defaults is cleaner",
			nil
		)
	end
	if definition.mirror ~= nil then
		grade(
			report,
			"aliases",
			"warning",
			"note",
			"note",
			"alias-mirror",
			"mirror alias is supported but miroir is cleaner",
			nil
		)
	end

	if type(definition.id) ~= "string" or definition.id == "" then
		addIssue(report, "error", "id", "definition needs a non-empty id", nil)
	elseif not safeIdentifier(definition.id) then
		grade(report, "id-style", "warning", "note", "warning", "unsafe-id", "id is not property-safe text", nil)
	end
	local currentVersion = if type(definition.version) == "number"
			and definition.version % 1 == 0
			and definition.version > 0
		then definition.version
		else 1
	if type(definition.version) ~= "number" or definition.version % 1 ~= 0 or definition.version <= 0 then
		grade(
			report,
			"version",
			"error",
			"warning",
			"warning",
			"version",
			"definition version should be a positive integer",
			nil
		)
	end
	if type(definition.pages) ~= "number" or definition.pages % 1 ~= 0 or definition.pages <= 0 then
		addIssue(report, "error", "pages", "definition pages must be a positive integer", nil)
	end

	local traits, traitsError = readTraits(definition)
	if traits == nil then
		addIssue(report, "error", "traits", traitsError or "missing traits", nil)
		return report
	end

	local rootCount = 0
	for fieldName, descriptor in traits do
		rootCount += 1
		if type(fieldName) ~= "string" then
			addIssue(report, "error", "root-field-name", "root field names must be strings", nil)
		else
			visitField(report, descriptor, fieldName, 1)
		end
	end
	if rootCount == 0 then
		addIssue(report, "error", "empty-traits", "traits table is empty", nil)
	end

	local defaults = definition.defaults or definition.defauts or {}
	visitDefaults(report, traits, defaults)
	visitMirror(report, definition, traits)
	visitMigrations(report, definition.migrations, currentVersion)
	applyCeiling(
		report,
		report.DeepestPath,
		opts.depthMax,
		"depth-ceiling",
		`schema depth {report.DeepestPath} exceeds ceiling {opts.depthMax}`
	)

	local compiledOk, compiledOrError = pcall(Compiler.compile, definition)
	if compiledOk then
		report.Schema = compiledOrError
		local schema = compiledOrError
		if schema.MirrorSize == 0 then
			grade(
				report,
				"mirror-bytes",
				"warning",
				"note",
				"warning",
				"empty-mirror",
				"compiled miroir size is zero",
				nil
			)
		end
		applyCeiling(
			report,
			schema.MirrorSize,
			opts.mirrorBytesMax,
			"mirror-bytes-ceiling",
			`miroir bytes {schema.MirrorSize} exceed ceiling {tostring(opts.mirrorBytesMax)}`
		)
		applyCeiling(
			report,
			#schema.MirrorEntries,
			opts.mirrorEntriesMax,
			"mirror-entries-ceiling",
			`miroir entry count {#schema.MirrorEntries} exceeds ceiling {tostring(opts.mirrorEntriesMax)}`
		)
		applyCeiling(
			report,
			schema.AlignmentWaste,
			opts.alignmentWasteMax,
			"alignment-waste-ceiling",
			`alignment waste {schema.AlignmentWaste} exceeds ceiling {tostring(opts.alignmentWasteMax)}`
		)
		applyCeiling(
			report,
			schema.SlackBytes,
			opts.slackBytesMax,
			"slack-bytes-ceiling",
			`slack bytes {schema.SlackBytes} exceed ceiling {tostring(opts.slackBytesMax)}`
		)
		applyCeiling(
			report,
			schema.PayloadBytes,
			opts.payloadBytesMax,
			"payload-bytes-ceiling",
			`payload bytes {schema.PayloadBytes} exceed ceiling {tostring(opts.payloadBytesMax)}`
		)
		if type(opts.slackRatioMax) == "number" and schema.PageBytes > 0 then
			local slackRatio = schema.SlackBytes / schema.PageBytes
			if slackRatio > opts.slackRatioMax then
				addIssue(
					report,
					if report.Mode == "creative" then "warning" else "error",
					"slack-ratio-ceiling",
					`slack ratio {string.format("%.3f", slackRatio)} exceeds ceiling {opts.slackRatioMax}`,
					nil
				)
			end
		end
		if schema.AlignmentWaste > 64 then
			grade(
				report,
				"alignment-waste",
				"warning",
				"note",
				"warning",
				"alignment-waste",
				`layout burns {schema.AlignmentWaste} bytes in alignment gaps`,
				nil
			)
		end
		if schema.SlackBytes > schema.PageBytes * 0.5 then
			grade(
				report,
				"page-slack",
				"warning",
				"off",
				"warning",
				"large-slack",
				`schema leaves {schema.SlackBytes} unused bytes in allocated pages`,
				nil
			)
		end
		if #schema.MirrorEntries > 64 then
			grade(
				report,
				"mirror-count",
				"warning",
				"note",
				"warning",
				"heavy-mirror",
				`miroir tracks many entries ({#schema.MirrorEntries})`,
				nil
			)
		end
		if schema.MirrorSize > schema.LayoutEnd * 0.5 then
			grade(
				report,
				"mirror-ratio",
				"warning",
				"note",
				"warning",
				"heavy-mirror-bytes",
				`miroir slice is large against layout ({schema.MirrorSize} / {schema.LayoutEnd})`,
				nil
			)
		end
		local lastEnd = schema.HeaderBytes
		for _, descriptor in ipairs(schema.Descriptors) do
			if descriptor.size <= 0 then
				addIssue(
					report,
					"error",
					"descriptor-size",
					"compiled descriptor has non-positive size",
					descriptor.path
				)
			end
			if descriptor.offset < schema.HeaderBytes then
				addIssue(
					report,
					"error",
					"descriptor-header-overlap",
					"compiled descriptor overlaps the reserved header",
					descriptor.path
				)
			end
			if descriptor.offset < lastEnd then
				addIssue(
					report,
					"error",
					"descriptor-overlap",
					"compiled descriptor overlaps the previous descriptor",
					descriptor.path
				)
			end
			lastEnd = math.max(lastEnd, descriptor.offset + descriptor.size)
		end
		if lastEnd > schema.LayoutEnd then
			addIssue(report, "error", "layout-overrun", "compiled descriptors extend beyond layout end", nil)
		end
		for _, descriptor in ipairs(schema.Descriptors) do
			local startPage = math.floor(descriptor.offset / 0x1000)
			local endPage = math.floor((descriptor.offset + math.max(descriptor.size - 1, 0)) / 0x1000)
			if endPage > startPage then
				grade(
					report,
					"cross-page",
					"off",
					"off",
					"note",
					"cross-page-field",
					"field crosses a page boundary",
					descriptor.path
				)
			end
		end
	else
		addIssue(report, "error", "compile", tostring(compiledOrError), nil)
	end

	return report
end

local function modeOptions(options: { [string]: any }?, mode: string)
	local out = if type(options) == "table" then table.clone(options) else {}
	out.mode = mode
	return out
end

function Lint.strict(definition: { [string]: any }, options: { [string]: any }?)
	return Lint.analyze(definition, modeOptions(options, "strict"))
end

function Lint.creative(definition: { [string]: any }, options: { [string]: any }?)
	return Lint.analyze(definition, modeOptions(options, "creative"))
end

function Lint.performance(definition: { [string]: any }, options: { [string]: any }?)
	return Lint.analyze(definition, modeOptions(options, "performance"))
end

return table.freeze({
	analyze = Lint.analyze,
	strict = Lint.strict,
	creative = Lint.creative,
	performance = Lint.performance,
})
