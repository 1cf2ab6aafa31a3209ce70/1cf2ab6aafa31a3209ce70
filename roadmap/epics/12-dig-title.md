# Epic 12 — Dig-the-ground title

**Outcome:** Ship an original offline excavation game as another independent title on the shared core, using the measured technique selected by spike 11.

**Entry:** Spike 11 selected a feasible mechanic and renderer; all earlier epics are complete. This is the final title in the initial roadmap and depends on all earlier ordered work.

**Starting scope:** [ADR-008](../decisions/ADR-008-dig-terrain-feasibility.md#scope) sets it to 2D excavation: SpriteKit `SKTileMapNode` drawing top-down depth bands over heightfield rules, with no physics. The first task removes the prototype's restart footprint growth (12.1–12.3 MiB over five simulator restarts). Its other simulator misses, the iPad scene-update share row and void iPhone 12 runs, are entry risks to measure again after that fix. 3D can be reopened only by a new decision record with new evidence, such as physical-hardware measurements or an idle comparison of `RealityView` and `ARView` hosts, never by changing the Spike 11 budgets applied to its runs.

## Scope and tasks

1. Define movement, excavation growth, object interaction, score/progression, boundaries, win/fail rules, and level format around the spike's scope choice.
2. Implement deterministic rule state and a separate rendering/physics adapter. Bound terrain updates, collision work, and allocations to the workload limits Spike 11 measured.
3. Create original arenas, art, audio, onboarding, accessible controls, pause/restart behavior, and feedback for successful digging and collection.
4. Validate every bundled level and asset; test save/restore mid-level only if the product design requires it, otherwise restart from a stable checkpoint.
5. Integrate through the existing module contract and apply the Epic 08 privacy, accessibility, performance, licensing, and release gates.

## Acceptance

- The complete game loop works offline on both simulator geometries within the workload limits Spike 11 recorded. Physical frame, memory and thermal behavior go through Epic 08's pre-distribution hardware check.
- Different render frame rates do not change rule outcomes for identical level, seed, and input fixtures.
- No dig-specific renderer or physics type leaks into `GameCore`, and existing titles still build and pass tests.
- The title has its own assets, bundle identity, save namespace, and release metadata; it ships with no ads, analytics, monetization, or app-originated network traffic.

**Outside this epic:** Procedural live-service content, accounts, and online competitions.
