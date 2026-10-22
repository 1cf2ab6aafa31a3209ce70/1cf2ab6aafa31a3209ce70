# Epic 09B — Tile match title

**Outcome:** Ship an original offline tile-match puzzle title as a separate app target whose rules differ from the block title, without duplicating shell code.

**Entry:** Epic 09A closed for rules, levels and play, passing the Epic 08 automated gates; its remaining checklist items are in [Polishing](../polishing.md). **Next:** Epic 10. This epic depends on all earlier ordered work.

**Polishing:** as for Epic 09A, original art, audio, animation, release metadata and hands-on or device accessibility steps go to [Polishing](../polishing.md) (owner decision, 2026-10-21). This epic closes on rules, levels and play that pass the automated gates.

## Scope and tasks

1. Define original rules, win/fail states, input model, scoring, and level progression. Document how they differ from the block title before sharing any genre code.
2. Implement pure board-state rules with deterministic seeds and tests for legal moves, matches or cascades, dead boards, undo/restart policy, and terminal conditions.
3. Build the SpriteKit scene, feedback, tutorial, accessible controls, and original art/audio. Keep board simulation separate from animation timing.
4. Author a curated bundled level set and validate every level. Use generation only where seeds and solvability checks make results reproducible.
5. Integrate title settings, level results, saves, localization, and release metadata through the module contract. Extract a small shared grid helper only if both finished titles need it.

## Acceptance

- The title offers a complete first-run-to-final-level path with no dead-end or impossible shipped level.
- It builds independently, saves separately, and passes the Epic 08 release checklist with no network or telemetry.
- Rule tests reproduce the same outcome from a recorded level/seed/input fixture; animation changes do not alter rules.
- Any helper extracted from the block title leaves that title's rule fixtures passing unchanged.
- Removing either match title leaves the other and the core building.

**Outside this epic:** Unscrew and terrain simulation; online leaderboards and live balance tuning.
