# Privacy-first native game-core roadmap

This is an ordered backlog for an open-source Apple-platform monorepo. The goal is to ship original unscrew/panel, block/tile match, and dig-the-ground games from one reusable core. Each linked epic or spike is a standalone brief. Complete the rows in order: every row inherits the decisions and completed work of all earlier rows.

## Product rules

- Games work offline. No ads, in-app purchases, analytics, attribution, crash-reporting SDKs, remote configuration, push notifications, accounts, or cloud sync.
- App code makes no network requests and requests no tracking permission. Saves and settings stay on the device. App Store distribution may involve Apple-operated services outside the app; privacy claims must describe the app accurately.
- Each title has its own identity, assets, levels, bundle identifier, and save namespace. Shared code owns lifecycle, settings, local progression, content loading, platform adapters, and common UI; title modules own rules and rendering.
- The repository uses first-party Apple frameworks by default. Any new dependency needs a written license, maintenance, privacy, and reproducibility review.
- Levels and art must be original or licensed for redistribution. Similar mechanics are acceptable; copied assets, level layouts, names, and store presentation are not.

## Ordered work

| Order | Type | Brief | Exit artifact |
| --- | --- | --- | --- |
| Preflight | Spike | [Open-source reuse audit](roadmap/spikes/preflight-open-source-reuse.md) | Build, privacy, license, and adoption decision for candidate repos |
| 00 | Spike | [Platform and rendering baseline](roadmap/spikes/00-platform-baseline.md) | Platform matrix and renderer decision record |
| 01 | Epic | [Repository and privacy foundation](roadmap/epics/01-foundation.md) | Buildable monorepo skeleton and contribution rules |
| 02 | Epic | [Shared app shell](roadmap/epics/02-app-shell.md) | Playable lifecycle shell on the chosen platforms |
| 03 | Spike | [Local save durability](roadmap/spikes/03-save-durability.md) | Save format and recovery decision record |
| 04 | Epic | [Local state and progression](roadmap/epics/04-local-state.md) | Versioned per-title saves and shared progression |
| 05 | Epic | [Bundled content and reproducible levels](roadmap/epics/05-content.md) | Validated level pipeline and deterministic QA fixtures |
| 06 | Spike | [Game-module seam](roadmap/spikes/06-module-seam.md) | Proven module contract with two render adapters |
| 07 | Epic | [Multi-title integration](roadmap/epics/07-module-integration.md) | Thin title targets and a reference game |
| 08 | Epic | [Quality and release baseline](roadmap/epics/08-release-baseline.md) | Repeatable privacy, accessibility, performance, and release checks |
| 09 | Epic | [Block and tile match titles](roadmap/epics/09-match-titles.md) | Two distinct, complete puzzle titles |
| 10 | Epic | [Unscrew/panel title](roadmap/epics/10-unscrew-title.md) | Complete unscrew title using the same core |
| 11 | Spike | [Dig-the-ground feasibility](roadmap/spikes/11-dig-feasibility.md) | Measured terrain interaction and renderer choice |
| 12 | Epic | [Dig-the-ground title](roadmap/epics/12-dig-title.md) | Complete terrain game using the same core |

The spikes are timeboxed decisions, not open-ended research. A failed spike must still produce evidence and an explicit scope decision. Later work starts only when the preceding row's exit criteria are met.

## Where existing repositories fit

| Candidate | Decision point | Potential use |
| --- | --- | --- |
| [Donpa Squad](https://github.com/vlumi/donpa) | Preflight → Epics 01, 02, 04, 07 | Study its pure game-core/UI split, thin platform targets, save strategy, and test setup. Audit and exclude its cloud, sharing, Game Center, and reserved brand assets. |
| [Leaves of Blocks](https://github.com/timveil/leaves-of-blocks) | Preflight → Epics 08–09 | Study block interaction, accessibility, localization, tests, and release tooling. Exclude local gameplay analytics and optional Game Center. |
| [GateEngine](https://github.com/STREGAsGate/GateEngine) | Preflight → Spike 00 | Compare a Swift 2D/3D engine against the smaller SpriteKit + RealityKit approach on the chosen devices. Adopt only if a measured vertical slice justifies its scope and dependencies. |
| [Voxels](https://github.com/heckj/Voxels) and [dynamic RealityKit mesh example](https://github.com/metal-by-example/metal-spatial-dynamic-mesh) | Spike 11 → Epic 12 | Test voxel storage/surface extraction and frequently updated RealityKit geometry for the dig mechanic. These are terrain references, not app shells. |

The preflight decision records whether each candidate will supply code, a narrow algorithm, an architectural pattern, or no reusable material. No candidate becomes a dependency by appearing in this table.

## Working definition of done

For every epic: build both debug and release configurations; run automated tests for pure logic and content validation; exercise the user-facing path on supported devices; update contributor documentation; and check that no app target acquired network, tracking, ad, commerce, or telemetry capabilities. Record the exact supported OS/device matrix in the repository after spike 00.

## Current workspace

This Git repository currently contains roadmap documents and no game source. The briefs describe a greenfield implementation; paths and target names are proposed, not references to existing code.

## Technical basis

Apple documents [SpriteKit on iOS and macOS](https://developer.apple.com/documentation/spritekit) and [SwiftUI `SpriteView`](https://developer.apple.com/documentation/spritekit/spriteview). For the 3D title, start with [RealityKit](https://developer.apple.com/documentation/realitykit) and test whether its rendering and physics meet the terrain mechanic's measured needs; Apple's [WWDC25 migration session](https://developer.apple.com/videos/play/wwdc2025/288/) recommends it for new 3D work. Apple's [privacy manifest guidance](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files) informs the release audit; the manifest and App Store privacy answers must reflect actual app behavior.
