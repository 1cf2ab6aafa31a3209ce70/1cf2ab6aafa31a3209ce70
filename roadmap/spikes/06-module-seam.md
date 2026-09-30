# Spike 06 — Game-module seam

**Decision needed:** Define the narrow contract that lets 2D puzzles and a terrain game share app services while retaining different simulations and renderers.

**Timebox:** Two developer days. **Entry:** Epic 05 level contract exists. **Next:** Epic 07.

## Investigation

1. Build two tiny modules: a grid board rendered through SpriteKit and a terrain placeholder rendered through the spike 00 candidate. Register each with the existing shell.
2. Exercise loading, pause/resume, input, success/failure, settings changes, and save callbacks in both. Identify any core API that exposes `SKScene`, RealityKit, or Metal types and remove that leakage.
3. Compare a protocol/factory registration API with generic or plugin-style designs. Favor the smallest compile-time API that permits separate game targets and testable pure rules.
4. Check whether a shared renderer abstraction actually reduces code. Keep only shared behavior demonstrated by both prototypes.

## Exit evidence

- Compiling prototypes, a documented registration interface, and a dependency diagram.
- Decision record with at least one rejected over-generalized API and a migration rule for evolving the module contract.
- A concrete list of capabilities that remain title-owned: simulation, hit testing, physics, rendering, and genre-specific UI.
