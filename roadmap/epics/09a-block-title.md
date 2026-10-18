# Epic 09A — Block match title

**Outcome:** Ship an original offline block-match puzzle title as its own app target, reusing the core without duplicating shell code. It is the first production title and the first to pass the Epic 08 release checklist.

**Entry:** Epic 08 release gates, Spike 11's contract decision and Epics 01–07 are complete. Epic 07's reference slice is the starting point. **Next:** Epic 09B. This epic depends on all earlier ordered work.

## Scope and tasks

1. Define original rules, win/fail states, input model, scoring, and level progression. Record them before writing any shared genre code.
2. Implement pure board-state rules with deterministic seeds and tests for legal moves, matches or clears, dead boards, undo/restart policy, and terminal conditions.
3. Build the SpriteKit scene, feedback, tutorial, accessible controls including a non-drag placement path, and original art/audio. Keep board simulation separate from animation timing.
4. Author a curated bundled level set and validate every level. Use generation only where seeds and solvability checks make results reproducible.
5. Integrate title settings, level results, saves, localization, and release metadata through the module contract.
6. Revisit the preflight findings on Leaves of Blocks for approved interaction or release patterns; keep its analytics/history and optional online features out.

## Acceptance

- The title offers a complete first-run-to-final-level path with no dead-end or impossible shipped level.
- It builds independently, saves separately, and passes the Epic 08 release checklist with no network or telemetry.
- Rule tests reproduce the same outcome from a recorded level/seed/input fixture; animation changes do not alter rules.
- Removing the title leaves the core and the other targets building.

**Outside this epic:** Tile match, unscrew and terrain mechanics; online leaderboards and live balance tuning.
