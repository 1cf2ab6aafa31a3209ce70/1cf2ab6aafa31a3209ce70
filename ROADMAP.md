# Privacy-first native game-core roadmap

This is an ordered backlog for an open-source Apple-platform monorepo. The goal is to ship original unscrew/panel, block/tile match, and dig-the-ground games from one reusable core. Current implementation targets iOS/iPadOS; macOS is deferred. Each linked epic or spike is a standalone brief. Complete the rows in order: every row inherits the decisions and completed work of all earlier rows.

## Product rules

- Games work offline. No ads, in-app purchases, analytics, attribution, crash-reporting SDKs, remote configuration, push notifications, accounts, or cloud sync.
- App code makes no network requests and requests no tracking permission. Saves and settings stay on the device. App Store distribution may involve Apple-operated services outside the app; privacy claims must describe the app accurately.
- Each title has its own identity, assets, levels, bundle identifier, and save namespace. Shared code owns lifecycle, settings, local progression, content loading, platform adapters, and common UI; title modules own rules and rendering.
- The repository uses first-party Apple frameworks by default. Any new dependency needs a written license, maintenance, privacy, and reproducibility review.
- Project-authored code, documentation and resources use the [MIT license](LICENSE); third-party material retains its own licenses and notices. Levels and art must be original or licensed for redistribution. Similar mechanics are acceptable; copied assets, level layouts, names, and store presentation are not.

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

**Current progress:** Preflight completed on 2026-09-30. The [reuse audit](roadmap/audits/preflight-open-source-reuse.md) retains Donpa and Leaves as references only and declines GateEngine; no candidate code or assets are included. **Spike 00 completed for mobile foundation development on 2026-10-01** under [ADR-003](roadmap/decisions/ADR-003-simulator-mobile-foundation.md), which replaces physical-device and macOS gates with simulator acceptance. The [retained evidence](roadmap/audits/spike-00-platform-baseline.md) includes successful Debug/Release simulator builds, eight pure tests and final interaction runs on iOS 26 simulators with iPhone 12 and iPad (9th generation) geometry. Simulator results do not establish physical performance or minimum-OS runtime behavior. **Epic 01 complete.** Its original mobile skeleton passed local builds, simulator checks and an independent clean filesystem-copy build, then [hosted CI](https://github.com/1cf2ab6aafa31a3209ce70/1cf2ab6aafa31a3209ce70/actions/runs/36933015783) passed on a clean committed checkout using Xcode 26.6 and iOS Simulator 26.5. The published documentation closure also passed [tip CI](https://github.com/1cf2ab6aafa31a3209ce70/1cf2ab6aafa31a3209ce70/actions/runs/36936690581/attempts/2); the [Epic 01 evidence](roadmap/audits/epic-01-mobile-foundation.md) retains both environments and its startup/cleanup observations. **Epic 02 complete.** The shared mobile controller/UI, title-owned practice, feedback and accessibility baseline passed all builds, 35 package tests and 13 app/UI tests per geometry. [Shell evidence](roadmap/audits/epic-02-app-shell.md) records source identity, review fixes and release limits. **Spike 03 complete.** [ADR-005](roadmap/decisions/ADR-005-local-save-durability.md) selects Codable snapshots and previous-good recovery, supported by [deterministic host filesystem fixtures](roadmap/audits/spike-03-save-durability.md). **Epic 04 complete for mobile simulator acceptance.** [Local-state evidence](roadmap/audits/epic-04-local-state.md) records durable preferences/progress, guarded migration and recovery, native player controls, 54 package tests, 21 app/UI tests per geometry and shutdown/boot restore proofs. The tested implementation also passed hosted CI. **Next: Epic 05**, bundled content and reproducible levels.

## Parallel work — 2026-10-01

| Track | Artifact / next action | Execution boundary |
| --- | --- | --- |
| Mobile foundation | [Epic 01](roadmap/epics/01-foundation.md), [contribution guide](CONTRIBUTING.md), [privacy contract](docs/privacy-contract.md), [content provenance](docs/asset-provenance.md) | Complete; local checks and hosted mobile CI passed |
| Mobile shell | [Epic 02](roadmap/epics/02-app-shell.md), [lifecycle decision](roadmap/decisions/ADR-004-mobile-shell-lifecycle.md), [evidence](roadmap/audits/epic-02-app-shell.md) | Complete; shared controller/UI, both simulator geometries and bundle/screenshot review passed |
| Mobile local state | [Epic 04](roadmap/epics/04-local-state.md), [storage decision](roadmap/decisions/ADR-005-local-save-durability.md), [evidence](roadmap/audits/epic-04-local-state.md) | Complete; versioned title saves, player controls and both local/hosted simulator restore proofs passed |
| Mobile validation | [Simulator acceptance record](roadmap/acceptance/spike-00-device-record.md) | Use simulators and available profiling; minimum-runtime and distribution checks remain explicit, without waiting for physical devices or Mac validation |
| Later spike preparation | [Scenario and evidence plans](roadmap/plans/later-spike-test-plans.md) | Spike 03 and Epic 04 are complete; Epic 05 builds the level pipeline. Spike 06 waits for Epic 05 and Spike 11 for Epic 10 |

Independent documentation and test planning may proceed in parallel. Later implementation keeps its listed dependencies; the revised simulator acceptance policy specifically enables Epic 01 and does not decide storage, module or final terrain contracts.

## Where existing repositories fit

| Candidate | Decision point | Potential use |
| --- | --- | --- |
| [Donpa Squad](https://github.com/vlumi/donpa) | Preflight → Epics 01, 02, 04, 07 | Reference its rules/render split, thin platform targets, save strategy, and tests. Its core also contains cloud/keychain adapters; no package or assets are approved for inclusion. |
| [Leaves of Blocks](https://github.com/timveil/leaves-of-blocks) | Preflight → Epics 08–09 | Reference block geometry, accessibility labels/reduced-motion patterns, localization checks, and CI structure. Accessible board placement needs independent work; analytics, Game Center, assets, and tooling remain excluded. |
| [GateEngine](https://github.com/STREGAsGate/GateEngine) | Preflight → Spike 00 | Declined by preflight for the starting foundation. Reconsider a measured comparison only if first-party prototypes reveal an unmet requirement; adoption needs a new dependency review. |
| [Voxels](https://github.com/heckj/Voxels) and [dynamic RealityKit mesh example](https://github.com/metal-by-example/metal-spatial-dynamic-mesh) | Spike 11 → Epic 12 | Test voxel storage/surface extraction and frequently updated RealityKit geometry for the dig mechanic. These are terrain references, not app shells. |

The preflight decision records whether each candidate will supply code, a narrow algorithm, an architectural pattern, or no reusable material. No candidate becomes a dependency by appearing in this table.

## Working definition of done

For every epic: build both debug and release configurations; run automated tests for pure logic and content validation; exercise the user-facing path on the supported mobile simulator geometries; update contributor documentation; and check that no app target acquired network, tracking, ad, commerce, or telemetry capabilities. Record runtime, geometry and source identity with validation results. iOS/iPadOS 18.0 is the deployment floor; minimum-runtime execution and distribution checks remain explicit under ADR-003. Physical devices and macOS are not required for current foundation work.

## Current workspace

This Git repository contains roadmap documents, the production mobile packages, a shared lifecycle shell and an original development practice. The disposable platform experiment under `experiments/platform-baseline` remains separate from production targets. Durable preferences and title-scoped practice progress are implemented. Puzzle rules, bundled levels and complete titles remain planned work.

## Technical basis

Apple documents [SpriteKit on iOS and macOS](https://developer.apple.com/documentation/spritekit) and [SwiftUI `SpriteView`](https://developer.apple.com/documentation/spritekit/spriteview). For the 3D title, start with [RealityKit](https://developer.apple.com/documentation/realitykit) and test whether its rendering and physics meet the terrain mechanic's measured needs; Apple's [WWDC25 migration session](https://developer.apple.com/videos/play/wwdc2025/288/) recommends it for new 3D work. Apple's [privacy manifest guidance](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files) informs the release audit; the manifest and App Store privacy answers must reflect actual app behavior.
