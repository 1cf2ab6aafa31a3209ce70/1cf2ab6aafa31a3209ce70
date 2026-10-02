# Spike 00 — Platform and rendering baseline

**Decision needed:** Which Apple OS versions, devices, input modes, and renderers can support the planned titles without forcing 3D terrain requirements into the shared core?

**Timebox:** Two developer days. **Entry:** The preflight reuse audit has a documented foundation decision. **Next:** Epic 01.

**Inherited decision:** [ADR-001](../decisions/ADR-001-first-party-foundation.md) starts with original first-party prototypes. Donpa and Leaves are references only; GateEngine was not retained, so investigation item 5 is conditional on reopening that decision for a measured unmet requirement. See the [preflight evidence](../audits/preflight-open-source-reuse.md) for build results and limitations.

**Current evidence (2026-09-30):** The [disposable sample](../../experiments/platform-baseline/README.md), [provisional ADR-002](../decisions/ADR-002-platform-rendering-baseline.md), and [execution report](../audits/spike-00-platform-baseline.md) are available. Acceptance hardware is iPhone 12 and iPad (9th generation); macOS release is deferred. Host/simulator builds and eight pure tests passed. The corrected collider and sustained-settling integration test passed on both device-geometry simulators; landscape containment assertions also passed on both geometries. Final Debug/Release host/simulator builds, eight pure tests and the source privacy scan passed. macOS pointer/keyboard interaction was observed in a partial run; full macOS runtime validation remains open. Final mobile landscape captures were visually inspected on both simulator geometries. Physical performance and minimum-runtime gates remain open. This spike is not complete.

## Investigation

1. Build a disposable SwiftUI shell with a SpriteKit scene on iPhone, iPad, and macOS hardware or simulators available to the team. Check resize, safe areas, pause/resume, touch, pointer, and keyboard input.
2. Draw a representative block/tile board and an unscrew panel. Measure frame pacing and memory on the oldest intended device; record device and OS, not an unqualified number.
3. Prototype a tiny deformable/diggable terrain scene in RealityKit using `RealityView`. Test its mesh updates, collision, and input on target devices; use Metal compute or a custom renderer only where the prototype demonstrates a need. Identify simulation, collision, and rendering responsibilities separately.
4. Choose minimum OS versions and whether macOS ships alongside mobile or follows later. State the acceptance hardware for later epics.
5. If preflight retained GateEngine as a candidate, build the same small board and terrain interactions in it and compare package cost, frame pacing, module fit, and maintenance burden with the first-party prototypes.

## Exit evidence

- An architecture decision record with the platform matrix, chosen 2D renderer, RealityKit terrain results, any justified Metal extension or fallback, a GateEngine decision if applicable, and measured prototype results.
- A buildable throwaway sample or checked-in experiment folder with instructions to reproduce measurements.
- A clear fallback if terrain interaction cannot meet the chosen frame and memory budgets; Epic 12 may become a 2D excavation game with the same player goal.

This spike decides technical feasibility. It does not build the production shell or the dig title.
