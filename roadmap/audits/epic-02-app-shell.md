# Epic 02 — Mobile app shell evidence

**Date:** 2026-10-01. **Branch:** `codex/mobile-app-shell`.

**Status:** Complete under the mobile simulator acceptance policy. The pre-publication local builds and tests passed, addressing the first ten review findings. Epic 01's published tip `0edf274` also passed [hosted run 36936690581, attempt 2](https://github.com/1cf2ab6aafa31a3209ce70/1cf2ab6aafa31a3209ce70/actions/runs/36936690581/attempts/2). The first hosted shell run failed during host package compilation. Two post-publication compatibility/checking fixes passed local verification; hosted confirmation is pending. The original local evidence remains preserved below.

## Implementation and acceptance coverage

| Requirement | Implementation and verification |
| --- | --- |
| Shared flow and title registration | `GameCore.ShellFlow` owns splash, menu, loading, playing, paused, result and load-error states. Request identity rejects stale preparation/completion; invalid transitions preserve state. Twenty-one pure tests cover legal/illegal actions, retry, pause overlap and settings language validation. |
| Playable sample, menus and renderer host | `GamePlatform.SharedShellView` and `ShellController` own reusable menus, settings, results and coordination. The title supplies copy, one retained `DevelopmentScene`, `SpriteView` and practice completion/end controls. App-hosted tests check scene identity, input gating, preparation lifetime and a second independent registration using the shared view/controller. UI paths exercise the controls. |
| Lifecycle and interruptions | Backgrounding, audio interruption, route loss and media-service reset pause input and playback. Foreground/interruption end never resumes automatically. Explicit Resume recovers focus only when available. Core, platform and app-hosted tests cover overlapping blockers and stale callbacks; UI tests cover home/reactivation. |
| Audio and haptics | First-party AVFAudio/UIKit/CoreHaptics adapters use ambient audio and optional supported haptics. Original PCM tones are generated in memory. Fourteen platform tests cover gating, notification ownership, recovery and audio format. No physical fidelity result is claimed. |
| Settings | Sound, music and haptics apply immediately for the current process. App and UI tests cover changes, retention through play/pause, and reset on termination. English is the supported language; no unused language picker or persistence layer is added. |
| Accessibility and layout | Semantic SwiftUI labels, headers and at least 44-point controls; scrollable safe-area layout; decorative scene hidden from accessibility; Reduce Motion removes the breathing action. UI tests exercise rotation, large text and reduced-motion traits. These tests do not replace a later VoiceOver audit. |
| Offline/privacy boundary | No app network or storage API, service SDK, permission prompt declaration, background mode or capability was added. The package graph remains local-only. Source and built-bundle review establish this boundary; there is no runtime packet-capture certification. |

The [lifecycle decision](../decisions/ADR-004-mobile-shell-lifecycle.md) and [content provenance](../../Games/DevelopmentTitle/CONTENT.md) record scope and original inputs. The development target uses one iPad window so it has one session owner. Puzzle rules, levels, durable saves, multiwindow sessions and the final multi-renderer contract remain separate roadmap work.

## Local verification

Local environment: Xcode 27.0 (`27A266a`), Swift 6.4 compiler in Swift 5 language mode, iOS Simulator 26.0 (`23A5287g`). Deployment floor: iOS/iPadOS 18.0. Simulator geometries: iPhone 12 and iPad (9th generation). Package tests run on the host; no macOS application target is built.

| Command / check | Result |
| --- | --- |
| `bash scripts/verify.sh /private/tmp/gamecore-epic02-accessible-verification-20261001` | Passed: generated-project and architecture/privacy checks, 21 core tests, 14 platform tests, Debug/Release generic simulator builds and unsigned Release generic iOS build. |
| `bash scripts/test-mobile.sh /private/tmp/gamecore-epic02-accessible-ui-20261001` | Passed on each geometry: nine app-hosted cases and four UI paths; zero failures, skips or result-summary runtime warnings. Both owned simulator UUIDs are absent from the post-run inventory. |
| Release bundle inspection | Simulator and unsigned iOS bundles contain only executable, Info.plist and PkgInfo. MinimumOSVersion is 18.0; the single-window manifest is present. No permission, background, URL-scheme, ATS override or service capability was added. Linked dependencies are Apple system frameworks/runtime only. DEBUG accessibility launch hooks are absent from Release. |

The [machine-readable evidence](epic-02-app-shell-evidence.json) records HEAD `940da81`, dirty state and SHA-256 of all 32 actual build/test inputs. That historical HEAD is not the tested implementation by itself: title integration, tooling and contrast changes were uncommitted. All 32 hashes matched the pre-publication source. After the two fixes below, 30 still match; the historical and current hashes for `Packages/GamePlatform/Package.swift` and `.github/workflows/mobile.yml` are recorded separately without rewriting the original inventory. Logs, inventory, operation logs and result bundles remain in the output directories above. Hosted CI retains package/build logs, simulator inventory and `.xcresult` bundles as `mobile-validation-evidence` for seven days.

Final playing, landscape and large-text result screenshots were reviewed on both geometries. Copy and actions remain readable without horizontal clipping; iPad content stays in the centered column, and iPhone landscape/large text scrolls to the requested controls. Explicit adaptive primary button text resolves the original contrast finding: sampled black text against retained light-mode teal/blue fills gives approximately 16.43:1 / 15.31:1. This is supporting screenshot evidence, not a dark-mode or full accessibility compliance audit. Exports remain at `/private/tmp/gamecore-epic02-accessible-iphone-screens` and `/private/tmp/gamecore-epic02-accessible-ipad-screens`.

## Post-publication verification

[Hosted shell run 36941455713](https://github.com/1cf2ab6aafa31a3209ce70/1cf2ab6aafa31a3209ce70/actions/runs/36941455713), attempt 1 at `a781051c0cf3672a1b0d169c8e6f4ede2c6817e8`, passed structural checks and all 21 core tests. `GamePlatform` then failed to compile: the implicit macOS package-host minimum was below the macOS 10.15 availability of `MainActor.assumeIsolated`. No mobile builds ran, and simulator tests were skipped. The same run's toolchain check reported success despite an `xcodebuild -version | head -1` broken-pipe exception.

The package now explicitly declares `.macOS(.v10_15)` for host logic tests alongside iOS 18.0. The app target remains mobile-only. The workflow captures the full version output once, checks the command's exit status and compares the exact two-line pinned version without an early-closing pipe.

`bash scripts/verify.sh /private/tmp/gamecore-epic02-host-floor-verification-20261001` passed after the manifest change: generated/architecture checks, all 35 package tests, Debug/Release generic simulator builds and unsigned Release iOS build. The captured-version check accepted the exact local Xcode version and correctly rejected the hosted Xcode 26.6 expectation on that different local toolchain. This does not establish a hosted pass. No additional local simulator run was performed for these host manifest/workflow changes; a new clean hosted run must confirm the pinned toolchain and mobile paths.

## Review findings

The small team independently reviewed core/platform integration, UI ownership, cancellation and built products. All findings below are addressed in source. The first ten passed the pre-publication checks; E02-11 and E02-12 passed local rechecks, with hosted confirmation pending.

| ID | Finding and disposition | Verification |
| --- | --- | --- |
| E02-01 | Addressed: a single app model would have shared its scene across advertised iPad windows. Declare one window. | Both final Release Info.plists contain `UIApplicationSupportsMultipleScenes=false`. |
| E02-02 | Addressed: a title-originated `CancellationError` could leave loading stuck. Current uncancelled requests now show recovery; shell-owned cancellation and stale requests are ignored. | Dedicated app-hosted recovery and cancellation tests. |
| E02-03 | Addressed: inactive play requests must not queue playback for foreground. | Platform inactive-play test passed. |
| E02-04 | Addressed: mobile output teardown stops players and releases only its activated session. | Source teardown review; observer deallocation and subscription tests passed. |
| E02-05 | Addressed: actual interruption end clears a stale resume failure message. | Source and app-hosted explicit recovery review. |
| E02-06 | Addressed: XCUITest center tap hit the SwiftUI toggle's label because its accessibility frame spans the row. Tap the trailing track and await the exact value. | Baseline recording/event inspection; final settings path passed on both geometries. |
| E02-07 | Addressed: a partly clipped heading was hittable after rotation, so test scrolling stopped too early. Await orientation and reveal the complete frame. | Baseline screenshot inspection; full-containment assertion retained and final rotation path passed on both geometries. |
| E02-08 | Addressed: a visible heading's actionability was not a valid scroll-completion criterion; an unnecessary window swipe invoked system UI and correctly paused play. Stop scrolling at full visibility, retain button actionability checks and drag within the named scroll view. | Second recording confirms play survived rotation, then paused only after the system gesture. Final rotation path passed on both geometries. |
| E02-09 | Addressed: title-local common UI/controller required another title to copy code. Move these into GamePlatform; keep title copy, renderer and practice rules in Games. | Independent review against the roadmap ownership rule; shared extraction and second registration fixture passed on both geometries. |
| E02-10 | Addressed: native tinted button labels had low contrast in screenshots. Use explicit adaptive primary text while retaining the native bordered backgrounds. | Initial samples were approximately 1.69:1 teal and 2.57:1 blue; final light-mode samples exceed 15:1 on both geometries. See the [W3C contrast reference](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html). Screenshot sampling is supporting evidence, not a full accessibility compliance audit. |
| E02-11 | Addressed: the implicit package-host minimum failed hosted compilation of `MainActor.assumeIsolated`. Declare macOS 10.15 for GamePlatform host logic tests while preserving iOS 18.0 and the mobile-only app. | Independent manifest/dependency review; post-fix local 35 package tests and three mobile builds passed. Pinned hosted recheck pending. |
| E02-12 | Addressed: the first-line toolchain pipe crashed `xcodebuild` while its check reported success. Capture complete version output once and compare the exact pinned version with command failure propagation. | Hosted log preserved the broken-pipe exception. Local exact-version acceptance and different-version rejection passed without the pipe. Pinned hosted recheck pending. |

The initial iPhone run at `/private/tmp/gamecore-epic02-ui-20261001` retained seven passing app-hosted tests and two passing/two failing UI paths. The second run at `/private/tmp/gamecore-epic02-final-ui-20261001` passed all eight app-hosted tests and three UI paths; its rotation path exposed E02-08. Both failures are preserved as diagnostic history, not acceptance evidence. The acceptance run includes the eighth cancellation-recovery case. No acceptance assertion was removed to make the harness pass.

## Remaining release checks and next work

Simulator development is accepted under [ADR-003](../decisions/ADR-003-simulator-mobile-foundation.md). There is no physical-device or macOS gate for this work. iOS 18 runtime execution, VoiceOver and wider accessibility inspection, actual audio/haptic fidelity, representative performance, runtime traffic observation, signing and store/privacy declarations remain release-baseline checks. An unsigned deployment-target build does not establish those results.

Epic 02 acceptance is closed. Next, [Spike 03](../spikes/03-save-durability.md) compares a versioned Codable file with the smallest justified local database alternative, proves interrupted-write recovery and an old-version migration, and chooses per-title save/settings ownership. [Epic 04](../epics/04-local-state.md) then implements durable local state. Spike 06 and Spike 11 retain their later entry gates.
