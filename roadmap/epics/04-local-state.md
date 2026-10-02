# Epic 04 — Local state and progression

**Outcome:** Each offline title can save settings and game progress safely, restore after termination, and migrate old saves without mixing data with another title.

**Entry:** Spike 03 selected and tested the save strategy; Epic 02 supplies the shell. **Next:** Epic 05. This epic depends on all earlier ordered work.

## Implementation — 2026-10-01

**Status:** Complete for the mobile simulator acceptance policy. Production preferences and title-scoped progress use versioned snapshots with guarded recovery, migration, reset, deletion and native export. Local and hosted validation passed all 54 package tests, mobile build configurations, 21 app/UI tests per geometry and shutdown/boot restore proofs. Independent review found no unresolved material issue. The [evidence report](../audits/epic-04-local-state.md) records source identity and acceptance coverage; [ADR-005](../decisions/ADR-005-local-save-durability.md) records the storage contract. Epic 05's entry gate is satisfied.

Physical reboot, hardware encryption, locked-device access and minimum-OS runtime execution remain outside this simulator evidence. Namespace isolation is exercised with two title IDs sharing a root; separate standalone title targets remain Epic 07 work. macOS application work remains deferred.

## Scope and tasks

1. Implement the versioned save envelope and atomic writer selected by spike 03, with a previous-good recovery path and explicit errors for unrecoverable data.
2. Define title-scoped save IDs, settings, completed levels, best score/stars if the game uses them, and unlock rules. Keep title-specific fields in versioned extensions rather than inflating shared models.
3. Implement load, save, migration, reset, and local export. Provide a clear UI confirmation before destructive reset.
4. Connect shell settings and result transitions to durable state. Prevent duplicate awards when a completion callback repeats.
5. Add fixtures for missing, corrupt, current, and old-version saves, and isolation between two title IDs.

## Acceptance

- Progress and settings survive app termination and device reboot on supported platforms.
- Interrupted write retains either the prior valid state or the new valid state; it never presents a partial save as valid.
- Known old saves migrate once; unknown future versions are preserved and reported without overwrite.
- Two title targets with the same level numbers never read or overwrite each other's saves.
- No profile, cloud sync, account, currency, streak, or leaderboard exists by default.

**Outside this epic:** Level data pipeline and gameplay rules.
