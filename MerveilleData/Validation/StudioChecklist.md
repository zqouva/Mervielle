# Studio Validation Checklist

`--> ["purpose"]`

This is to get you settled (in Studio).

---

`--> ["before you run"]`

- Make a place file dedicated to validation.
- Put the package under `ServerStorage/Packages/Merveille` (or your desired path).
- For client mirror tests, also make it available from `ReplicatedStorage/Packages/Merveille` if your project split needs that.
- Turn on Studio output.
- Use a disposable DataStore name if you are testing live save/open behavior.
- If you are only testing logic, set atelier options to `mock = true`.

---

`--> ["1. compile and lint"]`

In the command bar or a temporary server script:

```luau
local Merveille = require(game.ServerStorage.Packages.Merveille)
local PlayerReliquary = require(game.ServerStorage.Packages.Merveille.Examples.PlayerProfile)

print(Merveille.strict({
	id = "StrictCheck",
	version = 1,
	pages = 1,
	traits = { Lumen = Merveille.u32 },
	defaults = { Lumen = 0 },
	miroir = { "Lumen" },
}):text())

print(Merveille.creative({
	id = "CreativeCheck",
	version = 1,
	pages = 1,
	traits = { ["stage-name"] = Merveille.u32 },
	defaults = { ["stage-name"] = 0 },
	miroir = { "stage-name" },
}):text())

print(Merveille.performance({
	id = "PerformanceCheck",
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
}):text())
```

Expect:
- strict report passes on clean property-safe schema
- creative report stays usable on freer naming when structure is valid
- performance report prints layout and mirror metrics

---

`--> ["2. packet and vault validation"]`

Run:

- `Merveille/Validation/PacketValidation.server.luau`
- `Merveille/Validation/LintValidation.server.luau`
- `Merveille/Validation/ProfilerValidation.server.luau`

Expect output lines:

```text
[Merveille/Validation] packet, projection, authenticated vault, raw lanes, view, observatory checks passed
[Merveille/Validation] lint strict, creative, performance, defaults, migrations, and ceilings checks passed
[Merveille/Validation] runtime profiler checks passed
```

If any assertion fires, stop there.
DO NOT MOVE ON to live DataStore claims until all three pass.

---

`--> ["3. mock atelier open/save/close"]`

Create a temporary script:

```luau
local Merveille = require(game.ServerStorage.Packages.Merveille)
local PlayerReliquary = require(game.ServerStorage.Packages.Merveille.Examples.PlayerProfile)

local Atelier = Merveille.atelier("ValidationMock", PlayerReliquary, {
	mock = true,
	autosave = 60,
	vaultKey = Merveille.vaultKey("validation-secret"),
	vaultSlots = 4,
})

Atelier:matchVeille("1001", function(veille)
	veille.Lumen = 55
	veille.Title = "mock"
	veille.Aura.Clarity = 7.25
	veille:writeBlob("Memory", "sealed")
	assert(veille:trySave():isOk())
	assert(veille:tryClose("Mock"):isOk())
	print("mock open/save/close ok")
end, function(reason)
	error(reason)
end)
```

Expect:
- wake opens
- save succeeds
- close succeeds
- no decode, mac, or integrity warnings in output

---

`--> ["4. reopen and verify persistence"]`

Still in `mock = true` mode, reopen the same key in the same Studio session and verify:

```luau
local wake = Atelier:veille("1001")
assert(wake ~= nil)
assert(wake.Lumen == 55)
assert(wake.Title == "mock")
assert(wake.Aura.Clarity == 7.25)
print("mock reopen ok")
```

Expect the exact values.

---

`--> ["5. mirror keyframe, delta, xor"]`

Use the example client/server scripts or a local RemoteEvent pair.
Check:
- first client apply accepts a keyframe
- next apply accepts a reliable delta
- xor apply works after a matching base revision
- replaying a stale xor is rejected with `base revision mismatch`

If the client can do as it pleases without rejection, the pass failed.

---

`--> ["6. observatory report output"]`

From an opened wake:

```luau
local Observatory = Merveille.observatory(wake)
local html = Observatory:html(wake)
local dirty = Observatory:dirtyHtml(wake)
local svg = Observatory:svgDirtySpans(wake)
print(#html, #dirty, #svg)
```

Expect:
- non-zero output sizes
- visible `<svg` in the HTML text if printed or copied out
- dirty spans after you write to the wake

---

`--> ["7. profiler readout"]`

Open the mock atelier with `profile = true` and inspect both sides:

```luau
local Atelier = Merveille.atelier("ValidationProfile", PlayerReliquary, {
	mock = true,
	profile = true,
	vaultKey = Merveille.vaultKey("validation-secret"),
})

local wake = Atelier:veille("2002")
assert(wake ~= nil)

wake:add("Lumen", 10)
wake:write("Title", "profile")
wake:writeBlob("Memory", "profile")
wake:keyframe()
wake:add("Lumen", 5)
wake:mirror()
wake:add("Lumen", 1)
wake:xor()
wake:save()

print(Merveille.profiler(wake):text())
print(Merveille.profiler(Atelier):text())
```

Expect:
- wake profiler shows path/raw/blob/packet counters
- atelier profiler shows open/save/datastore timing counters
- output says profiling is enabled

---

`--> ["8. live datastore safety pass"]`

Only after mock mode passes:

- switch to a disposable DataStore name
- keep `vaultKey` enabled
- open a single key from one server
- save
- close cleanly
- reopen
- verify values
- then try opening the same key from a second server session to watch ownership handoff

Watch for:
- no endless open loop
- no silent save failure
- no payload decode failure
- no mac mismatch on honest reopen
- no stuck active lock after a clean release

---

`--> ["9. tamper sanity check"]`

If you have a controlled way to inspect the stored payload, flip one byte in the sealed record body and try to load it.
Expect the load to fail instead of returning altered data.
The source should reject the payload on authenticated open.

---

`--> ["10. what to record"]`

Record these before you call the pass complete:
- strict lint result text
- performance lint result text
- packet validation output
- profiler validation output
- mock atelier open/save/reopen output
- manual profiler readout output
- live disposable datastore open/save/reopen output
- any warnings from ownership handoff tests

