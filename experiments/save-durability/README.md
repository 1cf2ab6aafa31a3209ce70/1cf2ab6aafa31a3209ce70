# Save durability investigation fixture

This executable is an isolated [Spike 03](../../roadmap/spikes/03-save-durability.md) experiment. No app or production package depends on it. It uses Swift Codable, Foundation and platform POSIX calls; no remote dependencies or database library is added.

Run from the repository root:

```sh
swift run --package-path experiments/save-durability \
  --scratch-path /private/tmp/gamecore-save-durability-build save-durability-fixture
```

It creates a unique temporary root, runs deterministic assertions against real files, prints each result and removes its own root on normal exit. An assertion or filesystem failure exits unsuccessfully. Do not share or remove another run's directory.

## Envelope and file operations

[example-save-v2.json](example-save-v2.json) shows the complete representative envelope. A strictly validated lowercase title ID (`[a-z0-9-]`, 1–80 UTF-8 bytes) selects its own directory. Paths contain `save.json`, `save.previous.json`, and untrusted staging files `save.pending`/`backup.pending`. Readers never promote staging files. Schema and title headers are checked before interpreting progress. A one MiB bound is checked from file metadata before allocation and again before decode; this is an investigation limit, not a measured mobile product budget. The size check assumes one app writer owns this private directory, not adversarial concurrent file mutation.

Only both committed files being absent means first launch. Malformed known-schema primary data may recover a valid backup with an explicit backup-origin result. Future schema, alien title, unsupported old schema, oversized files and filesystem errors remain explicit; these records cannot silently fall back or be overwritten. Missing primary plus invalid backup also fails. Backup recovery must be acknowledged before a repair write. A valid primary may replace a corrupt backup, but a future or alien backup blocks replacement.

The writer validates the whole value and requires a revision greater than the latest readable committed revision. It writes a staged new save with a short-write loop and `fsync`, closes it, writes the previous validated value to a separate staged backup, closes it, renames that over the backup, then renames the staged new save over the primary. Rename stays within the same directory. Open/write/fsync/close/rename failures propagate. A corrupt primary is never rotated over a valid backup.

Schema 1 has integer completed levels, a total best score, and one sound flag. Migration deterministically sorts IDs into `level-N`, retains the total as `legacy-total` instead of inventing per-level scores, maps sound to music/effects, defaults haptics to true and language to English. It preserves revision during in-memory load. The explicit persisted migration increments revision; a subsequent load is schema 2 and does not migrate again. `level-1` is the safe initial unlock for this synthetic fixture. Actual title migration/unlock rules belong to Epic 04.

## Coverage and limits

31 scenarios cover first launch/round trip; first and subsequent writes interrupted after partial temporary write, flushed temporary, backup rename and primary rename; missing/corrupt current and backup; recovery acknowledgement; semantic corruption; known migration; unknown old/future versions; title isolation/collision/path traversal; stale/duplicate revisions; size and real filesystem error handling; ordered synthetic completion/pause/background snapshots; and inspectable export and delete-all operations.

Faults are injected as exceptions at named operation boundaries. A new store instance reads committed files after each interruption; files are real and not in-memory mocks. This proves application recovery selection and prevents partial-save acceptance in the exercised host process paths. It does **not** simulate operating-system crash, sudden power loss, device storage/controller behavior or iOS Data Protection. The fixture does not synchronize directory metadata, use Apple `F_FULLFSYNC`, model process termination inside rename, or certify physical durability. Those limits cannot be inferred from passing these assertions.

Pause/background events are synthetic sequence inputs, not live shell callbacks. The ordered loop proves latest-value behavior only under an explicitly serialized writer. Real lifecycle save hooks, queue serialization, cancellation/reset generation barriers, app termination/relaunch and device reboot behavior remain Epic 04 work. Export/delete-all are direct synchronous fixture operations; confirmation UI, user-selected export destinations, iOS Application Support/file protection/backup policy, title-specific validation, and settings integration are also production work. Delete-all removes both recovery slots and staging files to prevent old progress revival, removes the title directory and leaves a separately exported file intact. A separate Reset progress action that preserves preferences is a production requirement and is not implemented or proven by this fixture.

This fixture exercises a directory-read I/O error rather than claiming an iOS permission/protected-data simulation. No settings or revision is mirrored into UserDefaults. No cloud, profile, telemetry, import mechanism or generalized storage service is introduced.

The final [Release results](evidence/release-results.txt) and [run metadata/input hashes](evidence/run.json) retain the tested source identity and host toolchain.
