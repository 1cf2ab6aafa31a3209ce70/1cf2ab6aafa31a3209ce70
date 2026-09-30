# Spike 00 — Platform and rendering baseline

**Decision needed:** Which Apple OS versions, devices, input modes, and renderers can support the planned titles without forcing 3D terrain requirements into the shared core?

**Timebox:** Two developer days. **Entry:** Greenfield workspace. **Next:** Epic 01.

## Investigation

1. Build a disposable SwiftUI shell with a SpriteKit scene on iPhone, iPad, and macOS hardware or simulators available to the team. Check resize, safe areas, pause/resume, touch, pointer, and keyboard input.
2. Draw a representative block/tile board and an unscrew panel. Measure frame pacing and memory on the oldest intended device; record device and OS, not an unqualified number.
3. Prototype a tiny deformable/diggable terrain scene in RealityKit using `RealityView`. Test its mesh updates, collision, and input on target devices; use Metal compute or a custom renderer only where the prototype demonstrates a need. Identify simulation, collision, and rendering responsibilities separately.
4. Choose minimum OS versions and whether macOS ships alongside mobile or follows later. State the acceptance hardware for later epics.

## Exit evidence

- An architecture decision record with the platform matrix, chosen 2D renderer, RealityKit terrain results, any justified Metal extension or fallback, and measured prototype results.
- A buildable throwaway sample or checked-in experiment folder with instructions to reproduce measurements.
- A clear fallback if terrain interaction cannot meet the chosen frame and memory budgets; Epic 12 may become a 2D excavation game with the same player goal.

This spike decides technical feasibility. It does not build the production shell or the dig title.
