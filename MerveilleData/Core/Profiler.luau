--!strict

-->	["profiler"]
-->	Runtime performance profile layer for ateliers and wakes.
-->	This is not schema theory alone.
-->	It reads live counters collected by the runtime so you can inspect cadence,
-->	packet weight, save timings, mirror traffic, and mutation pressure.

local Profiler = {}
Profiler.__index = Profiler

local function cloneCounter(counter: any)
	if counter == nil then
		return {
			count = 0,
			ok = 0,
			err = 0,
			total = 0,
			max = 0,
			average = 0,
			bytes = 0,
		}
	end
	return {
		count = counter.count,
		ok = counter.ok,
		err = counter.err,
		total = counter.total,
		max = counter.max,
		average = if counter.count > 0 then counter.total / counter.count else 0,
		bytes = counter.bytes,
	}
end

local function countKeys(map: { [any]: any }): number
	local total = 0
	for _ in map do
		total += 1
	end
	return total
end

local function ms(seconds: number): string
	return string.format("%.3fms", seconds * 1000)
end

local function push(lines: { string }, value: string)
	lines[#lines + 1] = value
end

local function escapeHtml(value: string): string
	value = string.gsub(value, "&", "&amp;")
	value = string.gsub(value, "<", "&lt;")
	value = string.gsub(value, ">", "&gt;")
	return value
end

local function snapshotStore(store: any)
	local perf = store._perf or {}
	return {
		Kind = "Store",
		Enabled = perf.enabled == true,
		Store = store.Name,
		Schema = store.Schema.Id,
		Active = countKeys(store._active),
		PeakActive = perf.peakActive or 0,
		EncodedBytes = perf.encodedBytes or 0,
		DecodedBytes = perf.decodedBytes or 0,
		Opens = cloneCounter(perf.opens),
		Saves = cloneCounter(perf.saves),
		Mirrors = cloneCounter(perf.mirrors),
		Whispers = cloneCounter(perf.whispers),
		UpdateAsync = cloneCounter(perf.updateAsync),
		GetAsync = cloneCounter(perf.getAsync),
		RemoveAsync = cloneCounter(perf.removeAsync),
	}
end

local function snapshotWake(wake: any)
	local perf = wake._perf
	return {
		Kind = "Wake",
		Enabled = perf ~= nil,
		Key = wake:key(),
		Schema = wake._schema.Id,
		Revision = wake:revision(),
		Commit = wake:commit(),
		Active = wake:isActive(),
		Dirty = wake._dirty == true,
		DirtySpans = wake._spanCount,
		MirrorSpans = wake._mirrorSpanCount,
		PathWrites = if perf ~= nil then perf.PathWrites else 0,
		PathWriteBytes = if perf ~= nil then perf.PathWriteBytes else 0,
		VectorWrites = if perf ~= nil then perf.VectorWrites else 0,
		VectorWriteBytes = if perf ~= nil then perf.VectorWriteBytes else 0,
		BitsWrites = if perf ~= nil then perf.BitsWrites else 0,
		RawWrites = if perf ~= nil then perf.RawWrites else 0,
		RawWriteBytes = if perf ~= nil then perf.RawWriteBytes else 0,
		BlobWrites = if perf ~= nil then perf.BlobWrites else 0,
		BlobWriteBytes = if perf ~= nil then perf.BlobWriteBytes else 0,
		NumericOps = if perf ~= nil then perf.NumericOps else 0,
		ToggleOps = if perf ~= nil then perf.ToggleOps else 0,
		CompareExchanges = if perf ~= nil then perf.CompareExchanges else 0,
		Keyframes = if perf ~= nil then perf.Keyframes else 0,
		Deltas = if perf ~= nil then perf.Deltas else 0,
		Xors = if perf ~= nil then perf.Xors else 0,
		PacketBytes = if perf ~= nil then perf.PacketBytes else 0,
		DirtySpanPeak = if perf ~= nil then perf.DirtySpanPeak else 0,
		MirrorSpanPeak = if perf ~= nil then perf.MirrorSpanPeak else 0,
		MirrorRangeSyncs = if perf ~= nil then perf.MirrorRangeSyncs else 0,
		MirrorRangeCandidates = if perf ~= nil then perf.MirrorRangeCandidates else 0,
		MirrorRangeApplied = if perf ~= nil then perf.MirrorRangeApplied else 0,
		MirrorRangeBytes = if perf ~= nil then perf.MirrorRangeBytes else 0,
		Saves = cloneCounter(if perf ~= nil then perf.saves else nil),
	}
end

function Profiler.new(subject: any)
	local kind: string
	if type(subject) == "table" and subject._buffer ~= nil and subject._schema ~= nil then
		kind = "Wake"
	elseif type(subject) == "table" and subject.Schema ~= nil and subject._active ~= nil then
		kind = "Store"
	else
		error("[Merveille/Profiler] expected an atelier or wake")
	end
	return setmetatable({
		Kind = kind,
		Subject = subject,
	}, Profiler)
end

function Profiler:snapshot()
	return if self.Kind == "Store" then snapshotStore(self.Subject) else snapshotWake(self.Subject)
end

function Profiler:text(): string
	local snap = self:snapshot()
	local lines = {}
	if snap.Kind == "Store" then
		push(lines, `--> ["store profiler"] {snap.Store}`)
		push(
			lines,
			`schema={snap.Schema} enabled={tostring(snap.Enabled)} active={snap.Active} peakActive={snap.PeakActive}`
		)
		push(lines, `encodedBytes={snap.EncodedBytes} decodedBytes={snap.DecodedBytes}`)
		push(
			lines,
			`opens count={snap.Opens.count} ok={snap.Opens.ok} err={snap.Opens.err} avg={ms(snap.Opens.average)} max={ms(
				snap.Opens.max
			)}`
		)
		push(
			lines,
			`saves count={snap.Saves.count} ok={snap.Saves.ok} err={snap.Saves.err} avg={ms(snap.Saves.average)} max={ms(
				snap.Saves.max
			)} bytes={snap.Saves.bytes}`
		)
		push(
			lines,
			`mirrors count={snap.Mirrors.count} ok={snap.Mirrors.ok} err={snap.Mirrors.err} avg={ms(
				snap.Mirrors.average
			)} max={ms(snap.Mirrors.max)} bytes={snap.Mirrors.bytes}`
		)
		push(
			lines,
			`whispers count={snap.Whispers.count} ok={snap.Whispers.ok} err={snap.Whispers.err} avg={ms(
				snap.Whispers.average
			)} max={ms(snap.Whispers.max)}`
		)
		push(
			lines,
			`updateAsync count={snap.UpdateAsync.count} ok={snap.UpdateAsync.ok} err={snap.UpdateAsync.err} avg={ms(
				snap.UpdateAsync.average
			)} max={ms(snap.UpdateAsync.max)}`
		)
		push(
			lines,
			`getAsync count={snap.GetAsync.count} ok={snap.GetAsync.ok} err={snap.GetAsync.err} avg={ms(
				snap.GetAsync.average
			)} max={ms(snap.GetAsync.max)}`
		)
		push(
			lines,
			`removeAsync count={snap.RemoveAsync.count} ok={snap.RemoveAsync.ok} err={snap.RemoveAsync.err} avg={ms(
				snap.RemoveAsync.average
			)} max={ms(snap.RemoveAsync.max)}`
		)
		if not snap.Enabled then
			push(lines, "profiling is disabled; open the atelier with { profile = true } to collect runtime counters")
		end
	else
		push(lines, `--> ["wake profiler"] {snap.Key}`)
		push(
			lines,
			`schema={snap.Schema} enabled={tostring(snap.Enabled)} active={tostring(snap.Active)} revision={snap.Revision} commit={snap.Commit}`
		)
		push(
			lines,
			`dirty={tostring(snap.Dirty)} spans={snap.DirtySpans}/{snap.DirtySpanPeak} mirrorSpans={snap.MirrorSpans}/{snap.MirrorSpanPeak}`
		)
		push(
			lines,
			`pathWrites={snap.PathWrites} bytes={snap.PathWriteBytes} vectorWrites={snap.VectorWrites} vectorBytes={snap.VectorWriteBytes} bitsWrites={snap.BitsWrites}`
		)
		push(
			lines,
			`rawWrites={snap.RawWrites} rawBytes={snap.RawWriteBytes} blobWrites={snap.BlobWrites} blobBytes={snap.BlobWriteBytes}`
		)
		push(lines, `numericOps={snap.NumericOps} toggleOps={snap.ToggleOps} compareExchanges={snap.CompareExchanges}`)
		push(lines, `keyframes={snap.Keyframes} deltas={snap.Deltas} xors={snap.Xors} packetBytes={snap.PacketBytes}`)
		push(
			lines,
			`mirrorSyncs={snap.MirrorRangeSyncs} candidates={snap.MirrorRangeCandidates} applied={snap.MirrorRangeApplied} bytes={snap.MirrorRangeBytes}`
		)
		push(
			lines,
			`saves count={snap.Saves.count} ok={snap.Saves.ok} err={snap.Saves.err} avg={ms(snap.Saves.average)} max={ms(
				snap.Saves.max
			)} bytes={snap.Saves.bytes}`
		)
		if not snap.Enabled then
			push(lines, "profiling is disabled; open the atelier with { profile = true } to collect wake counters")
		end
	end
	return table.concat(lines, "\n")
end

function Profiler:html(): string
	local body = escapeHtml(self:text())
	return table.concat({
		"<!doctype html>",
		'<html><head><meta charset="utf-8"><title>Merveille Profiler</title></head>',
		'<body style="margin:0;padding:24px;background:#0f1014;color:#f4f4f5;font-family:ui-monospace, SFMono-Regular, Menlo, monospace;">',
		'<h1 style="margin:0 0 16px 0;font-size:24px;">Merveille Profiler</h1>',
		'<section style="background:#171922;border:1px solid #2a3142;border-radius:12px;padding:16px;">',
		'<pre style="margin:0;white-space:pre-wrap;">',
		body,
		"</pre>",
		"</section></body></html>",
	})
end

return table.freeze({
	new = Profiler.new,
})
