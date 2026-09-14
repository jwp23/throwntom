# Mascot drawing mutants are killed by geometry assertions and pixel probes

## Decision

The seven Mascot drawing views (`HeldPropView`, `FurnitureView`,
`TomatoFaceView`, `MascotView`, `TomatoBodyView`, `WornPropView`, `ArmsView`)
stay in mutation scope, and their survivors are killed with two kinds of
test, built once as shared helpers in `Tests/ThrowntomUITests`:

- **Path-geometry assertions** for deleted path segments and geometry
  arithmetic: element counts, bounding boxes and `Path.contains` on sampled
  points of the drawn `Path`.
- **Pixel probes** for deleted fills and strokes: render the view offscreen
  and assert the colour at a point that only that fill or stroke paints. This
  generalises the two probes `MascotSnapshotTests` already has.

No reference images are committed. Every view-layer survivor elsewhere in
`ThrowntomUI` gets a behaviour or render assertion too, cosmetic deletions
included; there is no cosmetic-exclusion rule.

## Rationale

- The 2026-09-14 baseline (throwntom-gz9z.1, run 34791789325) put 265 of 630
  gated mutants in these seven files: deleted `move`/`line`/`quad` segments,
  fills and strokes, and `*`/`-` swaps in geometry. Their tests assert
  placement and that every prop builds, not what is drawn, so one gap class
  accounts for 42% of the baseline.
- Reference images kill nearly everything with one mechanism but pin the
  renderer: CI runs `macos-15`, local runs a newer macOS, and every intentional
  art change re-records. A tolerance knob hides exactly the small deletions the
  mutants make.
- Geometry alone cannot see a deleted `.fill` or `.stroke`: the `Path` is
  unchanged, only the pixels are. The two existing probes show a targeted pixel
  check is cheap and deterministic, so the hybrid covers both classes without
  images in the repo.
- Excluding the art would need an ADR superseding ADR-016, which kept view
  files in scope so that missing-drawing gaps are reported; the same reasoning
  is why cosmetic view deletions get tests rather than exclusions.
- Options considered are recorded on throwntom-gz9z.1.35 and .36; the helper
  lands in throwntom-gz9z.1.37.
