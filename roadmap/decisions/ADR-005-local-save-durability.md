# ADR-005 — Local save durability

**Date:** 2026-10-01. **Status:** Accepted for Epic 04 implementation.

## Context

Standalone mobile titles need completion, best scores, unlocks and preferences to survive relaunch. These are small snapshots with no relational queries or concurrent writers. [Spike 03](../spikes/03-save-durability.md) compares a Codable file with system SQLite and tests failure/recovery outside production targets. The [comparison](../audits/spike-03-storage-comparison.md) records primary references and tradeoffs; the [fixture evidence](../audits/spike-03-save-durability.md) records what was actually exercised.

## Decision

Use first-party Swift Codable JSON and Foundation filesystem APIs in Application Support. Do not add SQLite, an ORM, a remote package or cloud service. Store progress and settings in one envelope, so an export, reset or replacement has one coherent state. UserDefaults does not own a second copy. The current shell keeps session-only preferences until Epic 04 connects this design.

Each title gets a directory under an app-owned save root using a strict, validated canonical identifier. Reject invalid identifiers rather than sanitizing them into collisions. The envelope includes `schemaVersion`, `titleID`, a monotonically increasing revision, completion/best-score records, unique unlock identifiers and sound/music/haptic settings. Title-specific fields get their own version when introduced; do not populate speculative currency, accounts or streaks. Bound file size before decoding and validate ranges, duplicates and required values afterward. The synthetic serialized example is retained with the fixtures.

One serialized writer owns a title's current file, staging file and previous-good backup. Write the full new snapshot to staging and synchronize it before promotion. Capture a validated previous state in the backup before atomically promoting the new current snapshot. Check and report every write, synchronization and replacement failure. A failed operation must leave the previous or new complete snapshot recoverable; never replace a good backup with corrupt or unsupported data. The host experiment demonstrates injected interruption boundaries, not a guarantee against device power loss. Epic 04 must validate the chosen filesystem calls on iOS and retain errors rather than reporting a save that did not finish.

Loading distinguishes these states:

- Neither current nor backup exists: create defaults. A stray staging file is never accepted as a committed save.
- Valid current: use it. A malformed obsolete backup does not invalidate a valid current.
- Missing or malformed current with valid backup: recover that backup explicitly and expose a recovery notice. Preserve damaged bytes until recovery is resolved; do not silently erase recoverable progress.
- No valid copy: expose an actionable error with reset/delete choices; validated export is unavailable without a valid snapshot; do not overwrite with defaults automatically.
- Unsupported future schema or a mismatched title in the selected recovery path: stop and preserve bytes. An older backup is not permission to downgrade an unsupported current save. Before writing, also validate the backup header and preserve unsupported or mismatched backup data even when current is valid.
- Permission, protection or other I/O failure: report temporarily unavailable storage; do not classify it as corruption or first launch.

Migrations operate on decoded known versions, validate the result and replace storage through the same backup/write path. Retain a v1-to-v2 fixture. Once v2 is committed, subsequent loads do not repeat the migration. Unknown future versions never migrate or save. Repeated result application preserves best-score maxima and set-like completions/unlocks rather than awarding duplicate progress.

Epic 04 must serialize lifecycle and result updates without relying on background callbacks always running. Persist at meaningful state changes; backgrounding is an additional flush opportunity. Reset/delete invalidates queued writes with a generation token before removing owned files, preventing a delayed result from resurrecting erased state.

## Mobile storage and player controls

Exclude the app-owned save directory and each promoted file from operating-system backup to honor the local-only product contract. Apply exclusion and protection to staging and backup staging before promotion, then verify final attributes after replacements and migrations. Use complete-until-first-user-authentication file protection so lifecycle saves can proceed after the first unlock; propagate protection-unavailable errors before that unlock. These platform attributes are requirements for Epic 04, not features proved by the host fixture. Apple references are retained in the comparison.

Provide native document export only after a deliberate player action, using the validated selected snapshot. Offer local Files storage and describe that a player-selected external provider may transfer the exported copy. The app sends nothing to the developer and provides no automatic sync or import. Excluding operating-system backup means uninstall or device loss can destroy progress; player-created exports are the available independent copies.

Separate confirmed **Reset progress** (preserve preferences) from confirmed **Delete local data** (remove progress, preferences and all owned recovery/staging files). Explain the scope before confirmation. Close any active session and invalidate pending saves first. Remove app-owned temporary exports; a copy already handed to the player's Files provider remains under their control.

## Consequences

Human-readable snapshots make inspection, export and known-version migrations straightforward. Whole-file writes and one backup suit current needs but are not a database transaction spanning unrelated files. Reconsider system SQLite only when measured snapshot size/write frequency or relational queries justify its additional schema and journal management.

[Evidence](../audits/spike-03-save-durability.md) closes the spike's format and deterministic-fixture exits. [Epic 04](../epics/04-local-state.md) still implements production storage, player controls, shell integration, iOS file attributes and simulator lifecycle validation. No physical device or macOS application work is required.
