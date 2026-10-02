# Spike 03 — Save durability evidence

**Date:** 2026-10-01. **Outcome:** Complete for the spike's decision and executable-fixture exits. [ADR-005](../decisions/ADR-005-local-save-durability.md) selects one versioned Codable JSON snapshot per title, with a previous-good backup. [Epic 04](../epics/04-local-state.md) implements production persistence next.

## Scope and comparison

The small team split executable fixtures, an independent storage/recovery review, and decision/evidence integration. The [comparison](spike-03-storage-comparison.md) evaluates Foundation/Codable versus system SQLite against completion, best score, unlocks and settings. The bounded snapshot needs no joins, indexed queries or multiple concurrent writers; SQLite adds schema/statement/journal management without an identified benefit. This is a qualitative choice, not a measured database benchmark. No third-party dependency, copied candidate source or asset was introduced.

The [disposable Swift executable](../../experiments/save-durability/README.md) uses real temporary filesystem files, bounded decoding, POSIX file synchronization and atomic rename on the host. It stays outside production packages and app targets. Its synthetic schema has title/version/revision, progress and settings; the retained example is inspectable JSON. No app network calls, telemetry, cloud or macOS application work was added.

## Tested recovery paths

The executable asserts absence and exact round trip; initial and subsequent writes interrupted after partial staging, flushed staging, backup promotion and current promotion; current corruption with a good backup; missing current with backup; corrupt/unrecoverable combinations; explicit recovery acknowledgment; known-version migration followed by a second load; future and wrong-title primary/backup preservation; duplicate/stale revisions; title namespace isolation; unsupported old versions; oversized inputs; actual filesystem I/O error propagation; sequential rapid updates; and synthetic export/delete-all behavior.

An interruption is an injected thrown error at a named boundary followed by reopening the store. It is **not** an operating-system process kill, reboot or power-loss test. File synchronization without directory synchronization is not a filesystem crash-durability certification. First-write failure before promotion returns absence and ignores staging. A replacement failure returns the previous or new intact record; recovery does not silently overwrite damaged or unsupported data.

The old fixture maps sorted numeric completion identifiers into level identifiers, preserves its historical total as `legacy-total` rather than inventing per-level scores, and maps one sound setting into explicit preferences. Loading does not mutate old bytes. Committing the migrated snapshot advances revision; the next load is current schema and does not repeat migration. These are synthetic migration rules, not an assertion that an earlier production schema exists.

## Verification and source identity

Final Release run passed **31/31 scenarios**, exit 0, on macOS 27.2 / arm64 using Xcode 27.0 (`27A266a`) and Swift 6.4. [Run metadata and SHA-256 inputs](../../experiments/save-durability/evidence/run.json) and [raw results](../../experiments/save-durability/evidence/release-results.txt) retain the command, environment and output. The builder and independent reviewer also each passed 31 Debug scenarios before the final scenario-label clarification; final Release hashes are authoritative. The implementation starts from `6e413a8` (completed mobile shell); the fixture hashes identify the added executable inputs independently of documentation commits.

Repository foundation checks and generated-project consistency pass. Production package/app/project inputs are unchanged. Mobile UI tests were not repeated for this experiment-only change; prior shell simulator evidence remains in [Epic 02](epic-02-app-shell.md).

## Limits carried into Epic 04

Synthetic sequential completion/pause/background labels prove ordered writes only. They do not exercise the actual shell, async writer cancellation, generation gates or background execution deadlines. Export validates JSON and cleanup validates owned-file scope; native Files export and confirmation UI remain unimplemented. Reset preferences and stale queued-write prevention must be tested in the production implementation.

The host temporary directory is an alternate test environment for the spike; it is not an iOS Application Support container. Epic 04 must apply and verify backup exclusion and file protection before promotion and after replacement, handle protection-unavailable errors, wire result/settings durability into the shell, and test relaunch/termination/recovery on iPhone 12 and iPad (9th generation) simulator geometries. Physical storage/power-loss, encryption and locked-device behavior are not certified. No physical device is required to continue mobile work.

These integration requirements do not leave the spike's narrow exit open: a format/recovery decision and deterministic interruption/migration fixtures exist. They are the explicit acceptance work of the next ordered epic.
