# Spike 11 — Dig-the-ground feasibility

**Decision needed:** Find a feasible way to render and simulate a satisfying excavation or hole-growth mechanic on the supported devices while preserving the existing core interface.

**Timebox:** Three developer days. **Entry:** Epic 10 is complete. **Next:** Epic 12.

## Investigation

1. Prototype the RealityKit terrain path from spike 00 with a small arena, continuous input, growing excavation, collectible objects, collision, restart, and pause/resume.
2. Compare a height field, voxel/chunk mesh, and a 2D visual approximation only to the extent needed to choose a mechanic. Measure frame pacing, memory, battery/thermal trend, and scene reload on the oldest target hardware.
3. Establish deterministic rule state independent of mesh timing. Test collision and scoring under different render frame rates.
4. Test accessibility and input on touch and any committed macOS platform. Identify a non-precision control path.
5. Recheck Apple's current renderer guidance before implementation. Keep RealityKit as the default; record measured reasons for any Metal compute/custom-renderer extension or SpriteKit approximation.
6. Evaluate [Voxels](https://github.com/heckj/Voxels) for data and surface generation and the [RealityKit dynamic-mesh example](https://github.com/metal-by-example/metal-spatial-dynamic-mesh) for mesh updates. Build only the narrow benchmark needed, then record license, API, performance, and adoption decisions.

## Exit evidence

- Reproducible prototype, device measurements, target budgets, decision record, and a risk list with mitigations.
- An explicit scope choice: deformable 3D terrain, simplified 3D chunks, or 2D excavation. Preserve the player fantasy while matching measured device limits.
- A confirmed `GameModule` integration path with no terrain-specific types added to core APIs.

If none meets the budget, Epic 12 starts with the 2D fallback instead of an unbounded engine project.
