# Merveille : v.0.1.0 : the beginning...
made by Makel/Savi(@sacredludt)

`--> ["what this is"]`

Merveille is a strict Luau data system built around one binary canvas.

The package center is:
- fixed memory layout
- direct property access
- binary-first persistence
- targeted ownership handoff
- compact mirrored outward slices
- reduced transient pressure
- inspectable offsets, lanes, and spans
---

`--> ["package shape"]`

```text
Merveille/
  init.luau
  README.md
  Core/
    Arena.luau
    Codec.luau
    Compiler.luau
    CRC32.luau
    Hash.luau
    Lint.luau
    Observatory.luau
    Option.luau
    Profiler.luau
    Projection.luau
    Result.luau
    SHA256.luau
    Signal.luau
    Store.luau
    Text.luau
    Vault.luau
    View.luau
    Wake.luau
    Xor.luau
  Examples/
    Boot.server.luau
    Lint.server.luau
    Miroir.client.luau
    Miroir.server.luau
    Phase4.client.luau
    Phase4.server.luau
    PlayerProfile.luau
    Profiler.server.luau
  Validation/
    LintValidation.server.luau
    PacketValidation.server.luau
    ProfilerValidation.server.luau

    README.md
    StudioChecklist.md
```

---

`--> ["public surface"]`

Core entry:

```luau
Merveille.reliquary(...)
Merveille.atelier(...)
```

Compile-time lint can be enforced too:

```luau
Merveille.reliquary(definition, { lint = "strict" })
Merveille.reliquary(definition, { lint = "creative" })
Merveille.reliquary(definition, { lint = "performance" })
Merveille.reliquary(definition, {
	lint = "performance",
	lintOptions = { mirrorBytesMax = 256, mirrorEntriesMax = 24 },
})
```

Schema forms:

```luau
Merveille.text(bytes)
Merveille.group(traits)
Merveille.rosary(element, capacity)
Merveille.bits(mapOrCount)
Merveille.blob(bytes)
```

Wake/session surface:

```luau
Atelier:veille(playerOrKey)
Atelier:mirror(playerOrKey)
Atelier:miroir(playerOrKey)
Atelier:whisper(playerOrKey, payload)
Atelier:sever(playerOrKey, force?)

Atelier:tryVeille(playerOrKey)
Atelier:matchVeille(playerOrKey, onOk, onErr)
Atelier:tryMirror(playerOrKey)
Atelier:matchMirror(playerOrKey, onOk, onErr)
Atelier:trySever(playerOrKey, force?)
Atelier:matchSever(playerOrKey, onOk, onErr, force?)

veille:save()
veille:flush()
veille:close(reason?)
veille:release(reason?)
veille:requiem(reason?)

veille:trySave()
veille:matchSave(onOk, onErr)
veille:tryClose(reason?)
veille:matchClose(onOk, onErr, reason?)
veille:tryMiroir()
veille:matchMiroir(onOk, onErr)

veille:read(path)
veille:write(path, value)
veille:add(path, number)
veille:sub(path, number)
veille:min(path, number)
veille:max(path, number)
veille:clamp(path, low, high)
veille:toggle(path, state?)
veille:compareExchange(path, expected, nextValue)

veille:offset(path)
veille:lane(path)
veille:rawLane(path)
veille:rawPage(index)
veille:rawBytes(offset, length)
veille:writeBytes(offset, source, sourceOffset?, length?)
veille:zero(offset, length)
veille:blob(path)
veille:writeBlob(path, source, sourceOffset?, length?)
veille:rawU8(offset)
veille:rawU16(offset)
veille:rawU32(offset)
veille:rawI8(offset)
veille:rawI16(offset)
veille:rawI32(offset)
veille:rawF32(offset)
veille:rawBool(offset)
veille:writeU8(offset, value)
veille:writeU16(offset, value)
veille:writeU32(offset, value)
veille:writeI8(offset, value)
veille:writeI16(offset, value)
veille:writeI32(offset, value)
veille:writeF32(offset, value)
veille:writeBool(offset, value)

veille:mirror()
veille:miroir()
veille:keyframe()
veille:xor()
veille:unreliable(keyframeEvery?)
veille:miroirUnreliable(keyframeEvery?)
```

Support libraries:

```luau
Merveille.signal()
Merveille.lint(definition, options?)
Merveille.strict(definition, options?)
Merveille.creative(definition, options?)
Merveille.performance(definition, options?)
Merveille.hash32(text)
Merveille.crc32(buffer, offset, length)
Merveille.sha256(source, offset?, length?)
Merveille.sha256hex(source, offset?, length?)
Merveille.encode(buffer, length?)
Merveille.decode(payload, length?)

Merveille.xor(target, targetOffset, left, leftOffset, right, rightOffset, count)
Merveille.xorInto(target, targetOffset, patch, patchOffset, count)
Merveille.xorMeasure(buffer, offset, count)

Merveille.projection(reliquary)
Merveille.miroirProjection(reliquary)
Merveille.view(reliquary, paths?)
Merveille.observatory(reliquaryOrWakeOrAtelier)
Merveille.profiler(atelierOrWake)
Merveille.performanceProfile(atelierOrWake)
Merveille.arena(byteSize, slotCount?)

Merveille.vaultKey(secretOrWords)
Merveille.sealBody(buffer, key)
Merveille.openBody(buffer, key)
Merveille.sealRecord(buffer, key, nonceSource?)
Merveille.openRecord(buffer, key)
Merveille.secureEqual(left, right)

Merveille.some(value)
Merveille.none()
Merveille.option(value)
Merveille.ok(value)
Merveille.err(reason)
```

Compatibility aliases remain:

```luau
Merveille.sanctum == Merveille.atelier
Merveille.scripture == Merveille.text
Merveille.chamber == Merveille.group
Merveille.array == Merveille.rosary
Merveille.stigmata == Merveille.bits
Merveille.velvet == Merveille.blob
```

---

`--> ["quick start"]`

## 1) define a reliquary

```luau
local Merveille = require(ServerStorage.Packages.Merveille)

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
		Marks = Merveille.bits({ Founder = 0, Beta = 1, Witness = 2 }),
		Memory = Merveille.blob(128),
	},
	defaults = {
		Lumen = 0,
		Rank = 1,
		Title = "",
		Murmur = "",
		Aura = { Grace = 0, Poise = 0, Clarity = 0 },
		Rosary = {},
		Marks = { Founder = false, Beta = false, Witness = false },
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
```

## 2) open an atelier

```luau
local bodyKey = Merveille.vaultKey("replace-this-with-your-own-secret")

local Atelier = Merveille.atelier("Players", PlayerReliquary, {
	autosave = 180,
	vaultKey = bodyKey,
	vaultSlots = 4,
	profile = true,
})
```

## 3) wake live data

```luau
local veille = Atelier:veille(player)
if not veille then
	player:Kick("Merveille could not open your reliquary.")
	return
end

veille.Lumen += 100
veille.Title = "Merveille"
veille.Marks.Founder = true
veille.Aura.Clarity = 8.25
veille.Rosary:push(9001)
```

## 4) close when done

```luau
veille:close("Manual")
```

---

`--> ["schema contract"]`

A reliquary accepts:

```luau
{
	id = "PlayerReliquary",
	version = 1,
	pages = 4,
	traits = { ... },
	defaults = { ... },
	miroir = { ... },
	migrations = { ... },
}
```

Accepted compatibility keys:

```luau
sigils   -> traits
fields   -> traits
mirror   -> miroir
defauts  -> defaults
```

The compiler produces:
- `ByPath`
- `Descriptors`
- `ReadByPath`
- `WriteByPath`
- `RootByName`
- `MirrorEntries`
- `MirrorByDescriptorId`
- generated scalar, text, bits, blob, and rosary accessors where that is valid
- layout metadata and schema hash

That keeps the runtime on compiled offsets instead of rediscovering the contract on every touch.

---

`--> ["data lint"]`

There is a data linter.

## strict

Strict mode is for people who want the schema to stay hard, property-safe, and expensive to get wrong.

```luau
local report = Merveille.strict(definition)
print(report:text())
assert(report:isOk())
```

Strict mode pushes on:
- structural validity
- property-safe field names
- duplicate miroir paths
- bit collisions
- explicit root defaults
- default value shape and scalar ranges
- sparse rosary defaults and unknown default keys
- migration table shape
- alias usage like `fields`, `sigils`, `mirror`, `defauts`

## creative

Creative mode keeps the structure, but it gives more freedom on what you can do.
If you wants freer names or a less rigid shape while they are still discovering what the reliquary wants to be, this is the mode for you.

```luau
local report = Merveille.creative(definition)
print(report:text())
```

Creative mode still rejects broken structure.
It just does not punish every `stylistic` choice the same way strict mode does.

## performance

Performance mode... Self-Explanitory? 
It works `mirror` weight, alignment waste, slack `bytes`, large `text` lanes, large `blob` lanes, wide `rosaries`, and configurable ceilings.

```luau
local report = Merveille.performance(definition)
print(report:text())
```

If you want lint enforcement during compile:

```luau
local PlayerReliquary = Merveille.reliquary(definition, {
	lint = "strict",
})
```

If you want hard ceilings:

```luau
local report = Merveille.performance(definition, {
	mirrorBytesMax = 256,
	mirrorEntriesMax = 24,
	textBytesMax = 96,
	blobBytesMax = 128,
	vecCapacityMax = 64,
	alignmentWasteMax = 32,
	slackRatioMax = 0.25,
})
```

---

`--> ["defaults and migrations"]`

That means:
- scalar defaults must match scalar kind and numeric range
- text defaults must fit the declared byte lane
- bit defaults must point at real bits and use booleans
- rosary defaults must be dense arrays within capacity
- group defaults must follow the same nested field shape as the reliquary
- unknown default keys are treated as schema mistakes

Migration tables are checked too.
Each source version step can be a function or a table with `up`.
The linter checks for broken entry shape, future-version mistakes, and missing steps between the earliest source version and the current `version`.

```luau
local definition = {
	id = "PlayerProfile",
	version = 3,
	pages = 1,
	traits = {
		Lumen = Merveille.u32,
		Title = Merveille.text(32),
	},
	defaults = {
		Lumen = 0,
		Title = "",
	},
	migrations = {
		[1] = function(state)
			state.Title = state.Title or ""
			return state
		end,
		[2] = {
			up = function(state)
				state.Lumen = state.Lumen or 0
				return state
			end,
		},
	},
}
```

---

`--> ["data kinds"]`

Scalars:

```luau
Merveille.u8
Merveille.u16
Merveille.u32
Merveille.i8
Merveille.i16
Merveille.i32
Merveille.f32
Merveille.bool
```

Text:

```luau
Title = Merveille.text(48)
```

Text stores `u16 length + fixed byte lane`.

Group:

```luau
Aura = Merveille.group({
	Grace = Merveille.f32,
	Poise = Merveille.f32,
	Clarity = Merveille.f32,
})
```

Rosary:

```luau
Rosary = Merveille.rosary(Merveille.u32, 128)
```

Usage:

```luau
veille.Rosary:push(9001)
veille.Rosary:last()
veille.Rosary:size()
veille.Rosary:find(9001)
veille.Rosary:contains(9001)
veille.Rosary:pop()
veille.Rosary:clear()
```

Bits:

```luau
Marks = Merveille.bits({ Founder = 0, Beta = 1, Witness = 2 })
```

Blob:

```luau
Memory = Merveille.blob(128)
```

Blob space is not just reserved. The wake has raw-lane helpers and blob write helpers for it.

```luau
veille:writeBlob("Memory", "sealed")
local copy = veille:blob("Memory")
```

---

`--> ["layout"]`

Current layout rules:
- page size: `0x1000`
- header size: `0x0100`
- scalars align to width up to 4 bytes
- text aligns to 2 bytes
- rosary stores `count + capacity + payload`
- bits pack into bytes
- groups flatten into the same canvas
- miroir entries pack into a compact second slice

That gives two related shapes:
1. the full wake body
2. the compact mirrored outward slice

The "client" owns the second one.
The live runtime/wake owns the first one.

---

`--> ["step 5"]`

## step 5) client mirror schema projection

Server side, a wake builds miroir packets.
Client side, a projection owns only the miroir bytes and applies packet updates in place.

```luau
local Projection = Merveille.projection(PlayerReliquary)
local ok, kind = Projection:apply(packet)
if ok then
	print(Projection:read("Lumen"))
	print(Projection:read("Aura.Clarity"))
end
```

Projection packet kinds:
- `1` keyframe
- `2` reliable raw delta
- `3` xor delta

Each delta carries a `baseRevision`.
If the client misses its base, the projection rejects the delt.

---

`--> ["step 6"]`

## step 6) unreliable xor path with periodic keyframes

Wake packet builders:

```luau
veille:keyframe()
veille:mirror()
veille:xor()
veille:unreliable(1.25)
veille:miroirUnreliable(1.25)
```

Behavior:
- first unreliable pulse returns a keyframe
- later pulses return xor deltas
- cadence returns to keyframes on interval
- reliable mirror path remains available separately

---

`--> ["views"]`

There are two compiled view directions.

## client miroir projection

```luau
local Projection = Merveille.miroirProjection(PlayerReliquary)
local state = Projection:project()
```

## schema read views

```luau
local View = Merveille.view(PlayerReliquary, {
	"Lumen",
	"Title",
	"Aura.Clarity",
	"Memory",
})

local snapshot = View:project(veille)
print(snapshot.Lumen, snapshot.Title, snapshot.Aura.Clarity)
```

A full schema view can read from:
- a live wake
- a read-only wake
- a raw full buffer

---

`--> ["operators"]`

```luau
veille:read("Lumen")
veille:write("Title", "phase 4")
veille:add("Lumen", 100)
veille:sub("Lumen", 25)
veille:min("Rank", 10)
veille:max("Rank", 2)
veille:clamp("Lumen", 0, 999999)
veille:toggle("Marks.Founder", true)
veille:compareExchange("Title", "phase 4", "phase 4 settled")
```

The raw-lane side is also exposed when you need exact byte control.

```luau
local offset = veille:offset("Lumen")
print(veille:rawU32(offset))
veille:writeU32(offset, 222)

local body, start, size = veille:lane("Memory")
local copy = veille:rawBytes(start, size)
veille:writeBytes(start, copy)
```

These are direct binary operations. They still mark dirty spans and update mirrored overlaps.

---

`--> ["try and match"]`

Rust-inspired carriers and flow helpers exist around atelier open/mirror and wake save/close/miroir paths.

Atelier side:

```luau
Atelier:matchVeille("123456", function(veille)
	print("opened", veille:key())
end, function(reason)
	warn("open failed", reason)
end)

local maybeView = Atelier:tryMirror("123456")
maybeView:match(function(view)
	print(view.Title)
end, function(reason)
	warn(reason)
end)
```

Wake side:

```luau
veille:matchSave(function()
	print("saved")
end, function(reason)
	warn("save failed", reason)
end)

veille:matchMiroir(function(packet)
	print(packet.Kind, packet.Length)
end, function(reason)
	warn(reason)
end)
```

Option / Result carriers:

```luau
local maybeWake = Merveille.option(Atelier:veille("123456"))
maybeWake:match(function(veille)
	print(veille:key())
end, function()
	warn("missing wake")
end)

local result = Merveille.ok("done")
result:match(function(value)
	print(value)
end, function(reason)
	warn(reason)
end)
```

---

`--> ["visual observatory"]`

The observatory emits standalone visual reports per wake.

Text reports:

```luau
local Observatory = Merveille.observatory(veille)
print(Observatory:layout())
print(Observatory:wake(veille))
print(Observatory:pageMap(veille))
```

Visual reports:

```luau
local pageSvg = Observatory:svgPageMap(veille)
local dirtySvg = Observatory:svgDirtySpans(veille)
local generalHtml = Observatory:html(veille)
local dirtyHtml = Observatory:dirtyHtml(veille)
```

`dirtyHtml` is a standalone "HTML" report for that wake.
It includes wake state, dirty span bars, mirror span bars, and page map visuals.

---

`--> ["runtime profiler"]`

If you want live counters instead of schema alone, open the atelier with profiling enabled.

```luau
local Atelier = Merveille.atelier("Players", PlayerReliquary, {
	mock = true,
	profile = true,
})
```

Then inspect either side:

```luau
local wakeProfile = Merveille.profiler(veille)
print(wakeProfile:text())

local atelierProfile = Merveille.profiler(Atelier)
print(atelierProfile:text())
```

The profiler tracks runtime surfaces like:
- open/save/mirror/whisper timings
- update/get/remove datastore call timings
- encoded and decoded byte totals
- wake path writes, raw writes, blob writes, vector writes, and bit writes
- keyframe, delta, and xor packet counts and bytes
- dirty span peaks and mirror span peaks
- mirror-range sync candidate counts and applied byte counts

You can read the raw snapshot too:

```luau
local snapshot = Merveille.profiler(veille):snapshot()
print(snapshot.Kind)
print(snapshot.Revision)
print(snapshot.PathWrites)
print(snapshot.Keyframes)
print(snapshot.PacketBytes)
```

Wake snapshots expose wake-oriented counters directly on the snapshot table.
Atelier snapshots expose store-oriented counters like `Opens`, `Saves`, `UpdateAsync`, `GetAsync`, `RemoveAsync`, `EncodedBytes`, and `DecodedBytes`.
The text report is only a formatted view over the same data.

It also emits standalone "HTML":

```luau
local html = Merveille.profiler(veille):html()
```

---

`--> ["stronger cryptography"]`

The stronger vault layer goes beyond plain body sealing.

There are two levels:

## compatibility body seal

```luau
Merveille.sealBody(bufferBody, key)
Merveille.openBody(bufferBody, key)
```

That keeps the older direct body-seal shape available.

## authenticated record seal

```luau
local key = Merveille.vaultKey("replace-this-with-your-own-secret")
Merveille.sealRecord(recordBuffer, key, "nonce-seed")
local ok, reason = Merveille.openRecord(recordBuffer, key)
```

The authenticated record layer adds:
- per-record nonce material
- derived subkeys
- XTEA body encryption
- HMAC-SHA256 authentication over the record with the MAC lane zeroed during digest
- seal version metadata in the header
- sealed flag in the header

Store integration uses the authenticated record path when `vaultKey` is configured.
The open path rejects a sealed payload that fails authentication or integrity.

Digest helpers are also exposed:

```luau
print(Merveille.sha256hex("abc"))
local digest = Merveille.sha256("abc")
```

There is also a constant-time equality helper for secret comparison work:

```luau
local same = Merveille.secureEqual("a", "a")
```

---

`--> ["workspace validation"]`

Validation files live in the workspace.

Read:

```text
Merveille/Validation/README.md
Merveille/Validation/PacketValidation.server.luau
Merveille/Validation/LintValidation.server.luau
Merveille/Validation/ProfilerValidation.server.luau
Merveille/Validation/StudioChecklist.md
```

That validation covers:
- sha256 known vector check
- keyframe application
- reliable raw delta application
- xor delta application
- stale `baseRevision` rejection
- full view projection
- blob lane writes
- raw scalar reads and writes
- authenticated record sealing and tamper rejection
- observatory dirty html/svg generation
- option/result usage
- strict lint mode
- creative lint mode
- performance lint mode
- default-shape, migration-shape, and mirror-budget lint validation
- runtime profiler validation for ateliers and wakes
- concrete Studio run order for mock and disposable live datastore validation

---

`--> ["surface coverage"]`

The package surface includes:
- raw offset and lane accessors
- generated field readers and writers
- reusable scratch arenas
- corruption and layout inspection tools
- compiled views
- richer operator vocabulary
- rust-style flow helpers
- standalone dirty-span html/svg reports
- client projection working with keyframes and deltas
- runtime profiler surfaces over atelier and wake activity
- schema linting in strict, creative, and performance modes

Pressure points that still deserve harder measurement:
- benchmark-driven refinement of operator costs
- deeper corruption reports naming exact failing regions
- more visual inspectors for mirrored slices and corruption sites
- stronger dashboards on top of observatory and profiler output
- real Studio and live-server measurement

---

`--> ["runtime notes"]`

Runtime posture:
- raw binary encode/decode path when available
- base64 fallback for compatibility
- `buffer.copy` and `buffer.fill` fast paths
- `buffer.writestring` and `buffer.readstring` fast paths
- compiled field readers and writers
- descriptor-driven miroir span queuing
- mirror page buckets for raw-range sync instead of scanning every mirrored entry on each touch
- reusable vault arena lanes for record sealing
- reliable raw deltas
- xor deltas
- periodic keyframe cadence
- authenticated record sealing when vault is enabled
- full views and client projections
- standalone observatory html/svg reports
- runtime profiling for ateliers and wakes when `profile = true`

---

`--> ["limits"]`

Limits:
- rosary remains scalar-only
- blob helpers are deeper than before but still not complete tooling
- validation files are written for Studio execution, not run in this workspace sandbox
- no benchmark rerun is being claimed here
- no proof against ProfileStore is being claimed here
- native C++ compilation is not exposed as a package path inside Roblox Luau, so the package pushes compiled accessors, authenticated sealing, raw lanes, linting, and validation instead of pretending otherwise

---

`--> ["files to read first"]`

```text
Merveille/init.luau
Merveille/Core/Compiler.luau
Merveille/Core/Wake.luau
Merveille/Core/Store.luau
Merveille/Core/Lint.luau
Merveille/Core/Projection.luau
Merveille/Core/View.luau
Merveille/Core/Vault.luau
Merveille/Core/SHA256.luau
Merveille/Core/Observatory.luau
Merveille/Core/Profiler.luau
Merveille/Validation/PacketValidation.server.luau
Merveille/Validation/LintValidation.server.luau
Merveille/Validation/ProfilerValidation.server.luau
Merveille/Validation/StudioChecklist.md
```

---

`--> ["execution state"]`

This documentation describes the package surface as it stands in source.
- I hope you enjoy using my package, this took me a while and yes i did actually cry while making the "manifesto".
