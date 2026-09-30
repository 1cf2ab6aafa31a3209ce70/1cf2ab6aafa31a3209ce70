# Epic 09 — Block and tile match titles

**Outcome:** Ship two original offline puzzle titles, one block match and one tile match, as separate app targets that reuse the core and demonstrate distinct rules without duplicating shell code.

**Entry:** Epic 08 release gates and Epics 01–07 core contracts are complete. **Next:** Epic 10. This epic depends on all earlier ordered work.

## Scope and tasks

1. Define original rules, win/fail states, input models, scoring, and level progression for each title. Document their differences before sharing genre code.
2. Implement pure board-state rules with deterministic seeds and tests for legal moves, cascades or matches, dead boards, undo/restart policy, and terminal conditions.
3. Build SpriteKit scenes, feedback, tutorials, accessible controls, and original art/audio. Keep board simulation separate from animation timing.
4. Author a curated bundled level set for each title and validate every level. Use generation only where seeds and solvability checks make results reproducible.
5. Integrate title-specific settings, level results, saves, localization, and release metadata. Extract a small shared grid helper only if both finished implementations need it.

## Acceptance

- Each title offers a complete first-run-to-final-level path with no dead-end or impossible shipped level.
- Both titles build independently, save separately, and pass the Epic 08 release checklist with no network or telemetry.
- Rule tests reproduce the same outcome from a recorded level/seed/input fixture; animation changes do not alter rules.
- A title can be removed without breaking the other or the core.

**Outside this epic:** Unscrew and terrain simulation; online leaderboards and live balance tuning.
