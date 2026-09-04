# Validation

`--> ["what this is"]`

These files are the in-workspace validation layer for the mirror, raw-lane, vault, linter, and profiler surfaces.

---

`--> ["files"]`

- `Validation/PacketValidation.server.luau`
  - validates sha256 known vector output
  - validates keyframe, reliable delta, xor delta, and stale base rejection
  - validates full view projection
  - validates blob writes and raw scalar lane access
  - validates authenticated record sealing and tamper rejection
  - validates observatory dirty html/svg output
  - validates option/result and wake try/match helpers
- `Validation/LintValidation.server.luau`
  - validates strict, creative, and performance lint modes
  - validates default-shape rules, ceiling enforcement, and migration validation shape
  - validates that strict mode rejects unsafe property names
  - validates that creative mode still permits freer schema style when structure is valid
- `Validation/ProfilerValidation.server.luau`
  - validates runtime profiler counters on ateliers and wakes
  - validates packet/build/save timing surfaces are exposed in profiler snapshots
- `Validation/StudioChecklist.md`
  - concrete Studio run order for compile, lint, packet, vault, mock atelier, profiler, and live disposable datastore checks

---

`--> ["how to run"]`

1. Put the package in Studio.
2. Run `Validation/PacketValidation.server.luau`.
3. Run `Validation/LintValidation.server.luau`.
4. Run `Validation/ProfilerValidation.server.luau`.
5. Use `Validation/StudioChecklist.md` for the full manual order.
6. Read the output.
7. If an assertion fires, the pass failed.

---

`--> ["what success means"]`

A passing validation confirms:
- the client projection accepts a keyframe and both delta kinds
- stale xor packets are rejected by `baseRevision`
- full schema views read the expected values
- blob and raw-lane helpers roundtrip expected bytes
- authenticated record sealing opens back correctly and rejects tampering
- the observatory emits standalone html/svg dirty reports
- lint catches invalid defaults, migrations, and budget ceilings
- runtime profiler surfaces expose atelier and wake counters
