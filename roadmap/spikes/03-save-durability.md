# Spike 03 — Local save durability

**Decision needed:** Choose a simple, versioned on-device save format and write/recovery strategy for multiple standalone titles.

**Timebox:** One developer day. **Entry:** Epic 02 shell exists. **Next:** Epic 04.

## Investigation

1. Compare a Codable file in Application Support with a local database only against actual needs: level completion, score, unlocks, and settings. No cloud or account design is in scope.
2. Simulate interrupted writes, corrupt data, absent files, an old schema, and a title identifier collision. Test atomic replacement and a previous-good backup.
3. Decide save envelope fields, schema versioning, migration tests, per-title directories, and whether settings belong in UserDefaults or the save file.
4. Document how a player can export, reset, and delete local data without contacting the developer.

## Exit evidence

- Decision record with example serialized data, migration rules, recovery behavior, and the smallest justified storage dependency set.
- Tiny executable fixtures proving an interrupted write and one old-version migration can be handled deterministically.

Do not build a generalized database layer unless the measurements and data model require one.
