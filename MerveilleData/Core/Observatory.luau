--!strict

-->	["observatory"]
-->	Inspection helpers for layout, dirty spans, page maps, payload integrity,
-->	and small visual reports.
-->	The output stays text-first, but Phase 4 also asked for inspectors that can
-->	render page maps and dirty spans visually, so the observatory now emits
-->	inline SVG and HTML reports as well.

local Codec = require(script.Parent.Codec)
local Wake = require(script.Parent.Wake)

local Observatory = {}
Observatory.__index = Observatory

local PAGE_SIZE = 0x1000

local function push(lines: { string }, value: string)
	lines[#lines + 1] = value
end

local function countBits(source: buffer): number
	local total = 0
	for index = 0, buffer.len(source) - 1 do
		local byte = buffer.readu8(source, index)
		for shift = 0, 7 do
			if bit32.band(byte, bit32.lshift(1, shift)) ~= 0 then
				total += 1
			end
		end
	end
	return total
end

local function formatDescriptor(descriptor: any, mirrored: { [string]: boolean })
	local mark = if mirrored[descriptor.path] then "*" else " "
	return string.format(
		"%s %-28s %-6s @%05d +%05d",
		mark,
		descriptor.path,
		descriptor.kind,
		descriptor.offset,
		descriptor.size
	)
end

local function wakeSubject(subject: any)
	return if type(subject) == "table" and subject._buffer ~= nil
		then subject
		else error("[Merveille/Observatory] expected an opened wake")
end

local function escapeHtml(value: string): string
	value = string.gsub(value, "&", "&amp;")
	value = string.gsub(value, "<", "&lt;")
	value = string.gsub(value, ">", "&gt;")
	return value
end

function Observatory.new(subject: any)
	local schema = subject
	if type(subject) == "table" then
		if subject.Schema ~= nil then
			schema = subject.Schema
		elseif subject._schema ~= nil then
			schema = subject._schema
		end
	end
	assert(
		type(schema) == "table" and type(schema.Descriptors) == "table",
		"[Merveille/Observatory] expected a compiled reliquary schema or wake/store with schema"
	)
	return setmetatable({
		Schema = schema,
	}, Observatory)
end

function Observatory:layout(): string
	local mirrored = {}
	for _, entry in ipairs(self.Schema.MirrorEntries) do
		mirrored[entry.path] = true
	end
	local lines = {}
	push(lines, `--> [\"layout\"] {self.Schema.Id} v{self.Schema.Version}`)
	push(
		lines,
		`pages={self.Schema.Pages} bytes={self.Schema.PageBytes} layoutEnd={self.Schema.LayoutEnd} mirrorBytes={self.Schema.MirrorSize}`
	)
	push(
		lines,
		`payloadBytes={self.Schema.PayloadBytes or 0} alignmentWaste={self.Schema.AlignmentWaste or 0} slackBytes={self.Schema.SlackBytes or 0} mirrorEntries={#self.Schema.MirrorEntries}`
	)
	push(lines, "* = mirrored into the client slice")
	for _, descriptor in ipairs(self.Schema.Descriptors) do
		push(lines, formatDescriptor(descriptor, mirrored))
	end
	return table.concat(lines, "\n")
end

function Observatory:wake(subject: any): string
	local wake = wakeSubject(subject)
	local header = Wake.readHeader(wake._buffer)
	local lines = {}
	push(lines, `--> [\"wake\"] {wake:key()}`)
	push(
		lines,
		`schemaHash={header.schemaHash} revision={header.revision} commit={header.commit} owner={header.ownerJobId}`
	)
	push(lines, `sealed={tostring(header.sealed)} sealVersion={header.sealVersion} active={tostring(header.active)}`)
	push(lines, `dirty={tostring(wake._dirty)} fields={countBits(wake._fieldDirty)} spans={wake._spanCount}`)
	push(
		lines,
		`mirrorRevision={header.mirrorRevision} mirrorBytes={self.Schema.MirrorSize} mirrorSpans={wake._mirrorSpanCount}`
	)
	for index = 1, wake._spanCount do
		push(lines, string.format("span[%d] @%05d +%05d", index, wake._spanOffsets[index], wake._spanLengths[index]))
	end
	for index = 1, wake._mirrorSpanCount do
		push(
			lines,
			string.format(
				"mirror[%d] @%05d +%05d",
				index,
				wake._mirrorSpanOffsets[index],
				wake._mirrorSpanLengths[index]
			)
		)
	end
	return table.concat(lines, "\n")
end

function Observatory:pageMap(subject: any): string
	local wake = wakeSubject(subject)
	local pageCount = self.Schema.Pages
	local dirtyPages = {}
	for index = 1, wake._spanCount do
		local offset = wake._spanOffsets[index]
		local size = wake._spanLengths[index]
		local first = math.floor(offset / PAGE_SIZE)
		local last = math.floor((offset + math.max(size - 1, 0)) / PAGE_SIZE)
		for page = first, last do
			dirtyPages[page + 1] = true
		end
	end
	local lines = {}
	push(lines, `--> [\"page map\"] {wake:key()}`)
	for page = 1, pageCount do
		local startByte = (page - 1) * PAGE_SIZE
		local mark = if dirtyPages[page] then "#" else "."
		local used = math.max(0, math.min(PAGE_SIZE, self.Schema.LayoutEnd - startByte))
		push(lines, string.format("page %02d %s @%05d used=%04d/%04d", page, mark, startByte, used, PAGE_SIZE))
	end
	return table.concat(lines, "\n")
end

function Observatory:svgPageMap(subject: any, columns: number?): string
	local wake = wakeSubject(subject)
	local pageCount = self.Schema.Pages
	local columnCount = math.max(1, columns or math.min(8, pageCount))
	local cellWidth = 84
	local cellHeight = 28
	local gap = 8
	local rows = math.ceil(pageCount / columnCount)
	local width = gap + columnCount * (cellWidth + gap)
	local height = gap + rows * (cellHeight + gap)
	local parts = {
		string.format(
			'<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">',
			width,
			height,
			width,
			height
		),
		'<rect width="100%" height="100%" fill="#111217"/>',
	}

	local dirtyPages = {}
	for index = 1, wake._spanCount do
		local offset = wake._spanOffsets[index]
		local size = wake._spanLengths[index]
		local first = math.floor(offset / PAGE_SIZE)
		local last = math.floor((offset + math.max(size - 1, 0)) / PAGE_SIZE)
		for page = first, last do
			dirtyPages[page + 1] = true
		end
	end

	for page = 1, pageCount do
		local row = math.floor((page - 1) / columnCount)
		local column = (page - 1) % columnCount
		local x = gap + column * (cellWidth + gap)
		local y = gap + row * (cellHeight + gap)
		local dirty = dirtyPages[page] == true
		local fill = if dirty then "#8e2f43" else "#263147"
		local stroke = if dirty then "#f29bb2" else "#7aa2ff"
		parts[#parts + 1] = string.format(
			'<rect x="%d" y="%d" rx="6" ry="6" width="%d" height="%d" fill="%s" stroke="%s" stroke-width="1"/>',
			x,
			y,
			cellWidth,
			cellHeight,
			fill,
			stroke
		)
		parts[#parts + 1] = string.format(
			'<text x="%d" y="%d" font-family="monospace" font-size="11" fill="#f4f4f5">p%02d</text>',
			x + 8,
			y + 13,
			page
		)
		parts[#parts + 1] = string.format(
			'<text x="%d" y="%d" font-family="monospace" font-size="10" fill="#d3d7e0">%s</text>',
			x + 8,
			y + 23,
			if dirty then "dirty" else "clean"
		)
	end

	parts[#parts + 1] = "</svg>"
	return table.concat(parts)
end

function Observatory:svgDirtySpans(subject: any, width: number?): string
	local wake = wakeSubject(subject)
	local chartWidth = math.max(320, width or 960)
	local rowHeight = 28
	local gap = 10
	local layoutBytes = math.max(self.Schema.LayoutEnd, 1)
	local mirrorRows = math.max(1, wake._mirrorSpanCount)
	local dirtyRows = math.max(1, wake._spanCount)
	local totalRows = dirtyRows + mirrorRows + 2
	local height = 40 + totalRows * (rowHeight + gap)
	local leftPad = 110
	local graphWidth = chartWidth - leftPad - 24
	local parts = {
		string.format(
			'<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">',
			chartWidth,
			height,
			chartWidth,
			height
		),
		'<rect width="100%" height="100%" fill="#111217"/>',
		'<text x="16" y="24" font-family="monospace" font-size="16" fill="#f4f4f5">dirty spans</text>',
	}

	local function bar(y: number, label: string, startOffset: number, size: number, fill: string, stroke: string)
		local x = leftPad + math.floor((startOffset / layoutBytes) * graphWidth)
		local w = math.max(2, math.floor((size / layoutBytes) * graphWidth))
		parts[#parts + 1] = string.format(
			'<text x="16" y="%d" font-family="monospace" font-size="11" fill="#cfd6e6">%s</text>',
			y + 16,
			label
		)
		parts[#parts + 1] = string.format(
			'<rect x="%d" y="%d" rx="5" ry="5" width="%d" height="18" fill="#1d2330" stroke="#39445b" stroke-width="1"/>',
			leftPad,
			y,
			graphWidth,
			18
		)
		parts[#parts + 1] = string.format(
			'<rect x="%d" y="%d" rx="5" ry="5" width="%d" height="18" fill="%s" stroke="%s" stroke-width="1"/>',
			x,
			y,
			w,
			fill,
			stroke
		)
		parts[#parts + 1] = string.format(
			'<text x="%d" y="%d" font-family="monospace" font-size="10" fill="#f4f4f5">@%d +%d</text>',
			x + 6,
			y + 13,
			startOffset,
			size
		)
	end

	local y = 40
	for index = 1, wake._spanCount do
		bar(y, `dirty[{index}]`, wake._spanOffsets[index], wake._spanLengths[index], "#8e2f43", "#f29bb2")
		y += rowHeight + gap
	end
	for index = 1, wake._mirrorSpanCount do
		bar(y, `mirror[{index}]`, wake._mirrorSpanOffsets[index], wake._mirrorSpanLengths[index], "#284c8f", "#8ab6ff")
		y += rowHeight + gap
	end

	parts[#parts + 1] = string.format(
		'<text x="16" y="%d" font-family="monospace" font-size="11" fill="#9ea8bd">layout bytes: %d</text>',
		height - 12,
		layoutBytes
	)
	parts[#parts + 1] = "</svg>"
	return table.concat(parts)
end

function Observatory:dirtyHtml(subject: any): string
	local wake = wakeSubject(subject)
	local wakeText = escapeHtml(self:wake(wake))
	local pageText = escapeHtml(self:pageMap(wake))
	local dirtySvg = self:svgDirtySpans(wake)
	local pageSvg = self:svgPageMap(wake)
	return table.concat({
		"<!doctype html>",
		'<html><head><meta charset="utf-8"><title>Merveille Dirty Report</title></head>',
		'<body style="margin:0;padding:24px;background:#0f1014;color:#f4f4f5;font-family:ui-monospace, SFMono-Regular, Menlo, monospace;">',
		'<h1 style="margin:0 0 16px 0;font-size:24px;">Merveille Dirty Report</h1>',
		'<div style="display:grid;grid-template-columns:1fr;gap:16px;">',
		'<section style="background:#171922;border:1px solid #2a3142;border-radius:12px;padding:16px;"><h2 style="margin:0 0 10px 0;font-size:16px;">wake</h2><pre style="margin:0;white-space:pre-wrap;">',
		wakeText,
		"</pre></section>",
		'<section style="background:#171922;border:1px solid #2a3142;border-radius:12px;padding:16px;"><h2 style="margin:0 0 10px 0;font-size:16px;">dirty spans</h2>',
		dirtySvg,
		"</section>",
		'<section style="background:#171922;border:1px solid #2a3142;border-radius:12px;padding:16px;"><h2 style="margin:0 0 10px 0;font-size:16px;">page map</h2>',
		pageSvg,
		'<pre style="margin:12px 0 0 0;white-space:pre-wrap;">',
		pageText,
		"</pre></section>",
		"</div></body></html>",
	})
end

function Observatory:html(subject: any): string
	local wake = wakeSubject(subject)
	local layout = escapeHtml(self:layout())
	local wakeText = escapeHtml(self:wake(wake))
	local pageText = escapeHtml(self:pageMap(wake))
	local svg = self:svgPageMap(wake)
	return table.concat({
		"<!doctype html>",
		'<html><head><meta charset="utf-8"><title>Merveille Observatory</title></head>',
		'<body style="margin:0;padding:24px;background:#0f1014;color:#f4f4f5;font-family:ui-monospace, SFMono-Regular, Menlo, monospace;">',
		'<h1 style="margin:0 0 16px 0;font-size:24px;">Merveille Observatory</h1>',
		'<div style="display:grid;grid-template-columns:1fr;gap:16px;">',
		'<section style="background:#171922;border:1px solid #2a3142;border-radius:12px;padding:16px;"><h2 style="margin:0 0 10px 0;font-size:16px;">layout</h2><pre style="margin:0;white-space:pre-wrap;">',
		layout,
		"</pre></section>",
		'<section style="background:#171922;border:1px solid #2a3142;border-radius:12px;padding:16px;"><h2 style="margin:0 0 10px 0;font-size:16px;">wake</h2><pre style="margin:0;white-space:pre-wrap;">',
		wakeText,
		"</pre></section>",
		'<section style="background:#171922;border:1px solid #2a3142;border-radius:12px;padding:16px;"><h2 style="margin:0 0 10px 0;font-size:16px;">page map</h2>',
		svg,
		'<pre style="margin:12px 0 0 0;white-space:pre-wrap;">',
		pageText,
		"</pre></section>",
		"</div></body></html>",
	})
end

function Observatory:corruption(payload: any): string
	local sourceBuffer: buffer
	if type(payload) == "buffer" then
		sourceBuffer = payload
	elseif type(payload) == "string" then
		sourceBuffer = Codec.decode(payload)
	else
		error("[Merveille/Observatory] corruption(...) expects a buffer or encoded string")
	end
	local ok, reason = Wake.verifyIntegrity(sourceBuffer, self.Schema)
	local header = Wake.readHeader(sourceBuffer)
	local lines = {}
	push(lines, `--> [\"corruption\"] {self.Schema.Id}`)
	push(lines, `ok={tostring(ok)} reason={reason or "none"}`)
	push(
		lines,
		`schemaHash={header.schemaHash} revision={header.revision} commit={header.commit} owner={header.ownerJobId}`
	)
	push(lines, `mirrorRevision={header.mirrorRevision} expectedSchemaHash={self.Schema.Hash}`)
	push(lines, `byteLength={buffer.len(sourceBuffer)} expectedPages={self.Schema.PageBytes}`)
	return table.concat(lines, "\n")
end

function Observatory:measure(label: string, iterations: number, fn: () -> ())
	assert(
		type(iterations) == "number" and iterations % 1 == 0 and iterations > 0,
		"[Merveille/Observatory] iterations must be a positive integer"
	)
	local started = os.clock()
	for _ = 1, iterations do
		fn()
	end
	local elapsed = os.clock() - started
	return {
		label = label,
		iterations = iterations,
		seconds = elapsed,
		perIteration = elapsed / iterations,
		perSecond = iterations / math.max(elapsed, 1e-9),
	}
end

return table.freeze({
	new = Observatory.new,
})
