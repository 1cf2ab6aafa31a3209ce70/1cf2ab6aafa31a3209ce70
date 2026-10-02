# Spike 00 — Platform and rendering baseline

**Decision needed:** Which Apple OS versions, devices, input modes, and renderers can support the planned titles without forcing 3D terrain requirements into the shared core?

**Timebox:** Two developer days. **Entry:** The preflight reuse audit has a documented foundation decision. **Next:** Epic 01.

**Inherited decision:** [ADR-001](../decisions/ADR-001-first-party-foundation.md) starts with original first-party prototypes. Donpa and Leaves are references only; GateEngine was not retained, so investigation item 5 is conditional on reopening that decision for a measured unmet requirement. See the [preflight evidence](../audits/preflight-open-source-reuse.md) for build results and limitations.

**Status (2026-10-01):** Complete for mobile foundation development under [ADR-003](../decisions/ADR-003-simulator-mobile-foundation.md). The user confirmed that no physical device is available and authorized simulator acceptance, MIT licensing and a mobile-only focus. macOS is deferred. iOS/iPadOS 18.0 is the deployment floor; minimum-runtime execution remains a distribution-readiness check when a compatible test environment is available.

The [disposable sample](../../experiments/platform-baseline/README.md) and [September 30 execution report](../audits/spike-00-platform-baseline.md) retain successful Debug/Release simulator builds, eight pure tests, and the final integration suite on iOS 26 simulators matching iPhone 12 and iPad (9th generation) geometry. Both geometry runs passed corrected terrain collision/sustained settling, touch/lifecycle and landscape containment checks. [ADR-002](../decisions/ADR-002-platform-rendering-baseline.md) preserves the original observations and budget proposals; its physical-device and macOS gates are superseded.

The [mobile simulator acceptance record](../acceptance/spike-00-device-record.md) separates accepted foundation evidence from future workload and distribution checks. No physical performance, thermal/battery, peak-memory or minimum-runtime pass is claimed. Epic 01's implementation entry gate is satisfied.

## Investigation

1. Build a disposable SwiftUI shell with a SpriteKit scene on iPhone and iPad simulators available to the team; macOS exploration is historical and deferred. Check resize, safe areas, pause/resume, touch, pointer, and keyboard input.
2. Draw a representative block/tile board and an unscrew panel. Record simulator update cadence and available memory metrics with the host, runtime and geometry; do not claim physical performance.
3. Prototype a tiny deformable/diggable terrain scene in RealityKit using `RealityView`. Test its mesh updates, collision, and input in the mobile simulator environment; use Metal compute or a custom renderer only where the prototype demonstrates a need. Identify simulation, collision, and rendering responsibilities separately.
4. Choose minimum OS versions and whether macOS ships alongside mobile or follows later. State the simulator acceptance matrix and release-validation limits for later epics.
5. If preflight retained GateEngine as a candidate, build the same small board and terrain interactions in it and compare package cost, frame pacing, module fit, and maintenance burden with the first-party prototypes.

## Exit evidence

- An architecture decision record with the platform matrix, chosen 2D renderer, RealityKit terrain results, any justified Metal extension or fallback, a GateEngine decision if applicable, and measured prototype results.
- A buildable throwaway sample or checked-in experiment folder with instructions to reproduce measurements.
- A clear fallback if terrain interaction cannot meet the chosen frame and memory budgets; Epic 12 may become a 2D excavation game with the same player goal.

This spike decides technical feasibility. It does not build the production shell or the dig title.
