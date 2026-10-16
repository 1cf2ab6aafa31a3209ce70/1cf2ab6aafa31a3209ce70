# Bundled content and reproducible fixtures

Each title owns its bundled levels and payload rules. `GameCore` supplies the shared envelope and deterministic test boundaries; it does not implement puzzle genres or import a renderer. The development fixtures demonstrate loading and validation for block match, tile match, unscrew/panel and dig-the-ground. They are small original examples, not complete or solvability-certified games.

## Author and validate

The development title links the local `Games/DevelopmentContent` package. Its copied `Resources` directory contains `catalog.json`, `Levels/*.json`, a declared original SVG and the algorithm notice. The loader locates the packaged catalog through `Bundle` resource lookup, covering the two observed toolchain resource layouts without retrying malformed content. The installed app reads this directory; the validator executable uses the same decoder and payload validators. No content download or user import path exists.

From the repository root:

```sh
swift run --package-path Games/DevelopmentContent content-validator
swift run --package-path Games/DevelopmentContent content-validator /absolute/path/to/Resources
swift test --package-path Games/DevelopmentContent
```

The first command checks the packaged samples; the second validates an authoring directory. A failed check exits nonzero with the affected file or identifier. `scripts/verify.sh` runs content tests and validation. The generated Xcode app target also validates its source resources before packaging; an invalid catalog must fail the build.

Catalog schema 1 declares `titleID`, a positive integer `contentVersion`, ordered level references (`id`, relative `file`, `gameType`), assets and optional localization keys. Level schema 1 declares the same stable `id`, `gameType`, matching content version, UInt64 `seed`, a title-owned `payload` and optional localization keys. Supported fixture types are `block`, `tile`, `unscrew` and `dig`. Paths are bounded bundle-relative components; absolute paths and traversal are rejected. JSON envelopes are bounded to 1 MiB. Assets are declared and must be present; missing files, duplicate IDs, mismatched versions, unknown references and invalid payload rules fail validation. The build-time inventory also rejects symlinks and undeclared files, so authoring traces cannot enter the copied resource directory unnoticed.

The fixture payloads deliberately model small constraints: bounded grids and unique in-range cells; paired tile tokens; uniquely named panels and screws with existing panel references; and a dig spawn distinct from target cells. Later titles own their complete rule schemas, solution guarantees, rendering and localization tables. Declaring a localization key validates a reference; it does not supply a translation.

## Stable identity and updates

A level's stable ID identifies the same progression achievement across releases. Order is presentation, never identity. Reordering a catalog or changing its content version must not rewrite saved completion, best scores or unlocks for unchanged IDs. Keep a stable ID when the achievement remains equivalent. Assign a new ID when its meaning changes materially; retain historical progress for removed IDs rather than silently deleting it. Never reuse an old ID for an unrelated level.

A future title may introduce an explicit, reviewed mapping from old IDs to new ones. That migration must preserve unchanged IDs and earned records, handle collisions deliberately, and be tested against old saves. The default policy performs no automatic positional mapping or deletion. The content schema version is independent of the local save schema version.

## Reproduction boundaries

Rules consume the level's content version, seed and explicit input ticks. Rendering frame rate and wall-clock time must not determine rule outcomes. The generator uses the fixed SplitMix64 integer formula with explicit rejection sampling; [its provenance review and notice](../roadmap/audits/preflight-inclusion-bom.md) identify the public-domain algorithm source. The algorithm and bounded sampling behavior form part of the reproduction contract: changing them requires a deliberate version/fixture update. Seeds reproduce only the same rules and content; a seed alone cannot identify a changed level.

Replay inputs belong in developer fixtures. Production local saves remain necessary completion, score and unlock records; they do not acquire input traces, tester reports or device identifiers. The reference fixture simulations are validation tools, not production gameplay or a final game-module interface. Spike 06 decides that interface after this content contract is accepted.

## Local playtest report

Copy this template into a local file and share it manually through your chosen channel. The app never uploads it. Use a build commit or version that identifies the tested implementation. Include an input fixture only when deliberately reproducing a developer test; do not collect player sessions.

```text
Title:
Build version / commit:
Level stable ID:
Content version:
Seed:
Device model or simulator geometry:
OS / simulator runtime:
Steps or developer input fixture:
Expected behavior:
Observed issue:
Optional screenshot or local fixture path:
```

For mobile development, use iPhone 12 and iPad (9th generation) simulator geometry. Simulator results do not establish physical performance, locked-device behavior or minimum-runtime execution. macOS application development remains deferred.
