# Epic 10 — Unscrew/panel title

**Outcome:** Ship an original panel-removal puzzle title using the established offline shell, local progression, bundled levels, and release gates.

**Entry:** Epic 09 proved multiple production titles; all earlier core work is complete. **Next:** Spike 11. This epic depends on all earlier ordered work.

## Scope and tasks

1. Specify screw placement, panel overlap, supported removal order, hole occupancy, gravity/physics policy, win/fail states, and undo/restart behavior. Pick a deliberately small mechanic set for the first release.
2. Implement a deterministic rules model for constraints and moves. Treat visual physics as presentation unless a physics outcome is part of the puzzle rules; if it is, define a reproducible simulation strategy.
3. Build input and hit testing for small screws, clear animation and feedback, tutorial levels, accessible alternatives to precision dragging, and original audiovisual assets.
4. Add an authoring/validation tool that detects duplicate IDs, invalid overlaps, missing assets, and unsolvable or ambiguous levels where the solver can prove them. Manually review cases beyond solver reach.
5. Integrate saves, settings, localization, and release metadata through the existing title contract; apply all Epic 08 gates.

## Acceptance

- Every shipped level has a verified solution path and clear failure/reset behavior.
- Background/resume, interrupted animations, rapid repeated taps, and undo cannot desynchronize visual and rule state.
- The title builds independently, remains fully playable offline, and introduces no telemetry, commerce, or network dependency.
- Its gameplay code and assets are title-owned; shared core changes are limited to justified reusable capabilities.

**Outside this epic:** Terrain rendering and remote level updates.
