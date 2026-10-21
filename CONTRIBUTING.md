# Contributing

This repository contains an original mobile foundation, a playable lifecycle shell and a separate [disposable platform experiment](experiments/platform-baseline/README.md). Production settings and practice progress persist locally. Original development level fixtures exercise bundled loading and validation; complete puzzle rules and titles remain roadmap work.

## Start here

Read the [roadmap](ROADMAP.md), [first-party foundation decision](roadmap/decisions/ADR-001-first-party-foundation.md), and [mobile simulator acceptance policy](roadmap/decisions/ADR-003-simulator-mobile-foundation.md). Current production targets are iOS/iPadOS 18.0 and later. Use simulators with iPhone 12 and iPad (9th generation) screen geometry; no physical device is required for this work. macOS development and release are deferred.

The configured CI baseline is the `macos-26` runner with Xcode 26.6 (`17F113`) and iOS 26.5 simulator runtime. Xcode 27.0 (`27A266a`) with Swift 6.4 and the iOS 26.0 simulator runtime is the observed local environment. Packages and targets use Swift 5 language mode. Keep recorded results tied to the actual toolchain/runtime: a local pass does not mean the configured remote workflow has run.

Use Python 3.9 or newer for the standard-library project/check/test scripts. From the repository root:

```sh
bash scripts/verify.sh
bash scripts/test-mobile.sh
```

The first command checks generated-project consistency and architecture/privacy boundaries, runs core, platform and title-content tests, validates bundled fixtures, and builds Debug/Release for a generic simulator plus unsigned Release for generic iOS. The second runs app-hosted model and UI tests on the two selected simulator geometries. It runs a failed case once more, names every retry in `<model>-retries.json`, a `RETRIED` line and a CI warning, and checks each failed run against the simulator input fault behind [N06](roadmap/audits/mobile-navigation-contact.md). A failed run without a matching fault may be an app defect: investigate it and record it in that audit. Open `GameCore.xcworkspace` with scheme `DevelopmentTitle`. Follow the [root README](README.md) for project generation, simulator selection and exact tool requirements. Tests cover meaningful transitions, preparation, feedback lifetime and user-facing shell paths. These checks do not certify a complete game, physical performance, runtime privacy or minimum-OS execution.

The disposable experiment has its own build/test commands in its README. Its renderer integration evidence does not make the experiment a production package or title.

## UI test failures

Read the simulator's log before changing app code, test input or instrumentation. Every failed result bundle carries it:

```sh
xcrun xcresulttool export diagnostics --path <model>.xcresult --output-path <dir>
find <dir> -name system.logarchive
/usr/bin/log show --archive <archive> --info --debug --style compact \
  --predicate 'process == "backboardd" AND category == "TouchEvents"'
```

Call `/usr/bin/log` by full path, because zsh has its own `log` builtin.

A control that renders pressed but runs no action, or a toggle that does not change, is usually the simulator fault behind [N06](roadmap/audits/mobile-navigation-contact.md). backboardd logs `*** unknown digitizer`, or initializes a `BKDirectTouchState` more than 100 ms after `digitizer attached`. The fault drops or compresses an XCTest synthesized gesture before the app receives it, in roughly 1 of 400 gestures on loaded hosted runners (five faults in 15 full hosted runs), and no app change can prevent it. A synthesized hardware button press can fail the same way: SpringBoard receives the release late, a click reads as a hold, and testmanagerd logs a `ButtonEventsCompleted` timeout (N09). A launch can also time out on the host side before the app starts; the failure names "Timed out while launching application via Xcode" (N10). The collector already retries the case and records the match under `inputFaults` in `<model>-retries.json`, so nothing more is needed. From 2026-10-04 to 2026-10-18 this signature was investigated with a longer press, an action journal and scroll- and touch-phase observers before anyone read this log. Do not repeat that.

A system view that fails to appear, such as the Files exporter, may still be launching. Its first launch on a fresh hosted simulator took 24 seconds (N07), so wait generously for out-of-process system UI. A wait can also run out inside one slow accessibility query on a loaded runner (N08). Before suspecting the app, compare the failure time with the fixture journal and the screen recording in the result bundle.

## Changes and ownership

Keep changes focused and explain the behavior or decision they change. Include relevant validation and remaining uncertainty. Preserve the roadmap's dependencies unless an explicit decision revises them. Simulator results must be labeled with runtime and geometry; a deployment-target build is not execution on the minimum OS.

Feature branches target `integration/first-party-foundation`. Promotion PRs carry reviewed integration history to `main` and add no content of their own. Land any fix a promotion needs on integration first, then promote again. If content does reach `main` directly, merge `main` back into integration through a PR before further integration work. Promotion merge commits that exist only on `main` are harmless; content commits there conflict with the next promotion, as in [PR 10](https://github.com/1cf2ab6aafa31a3209ce70/1cf2ab6aafa31a3209ce70/pull/10).

Scale evidence to the change. Shared packages, the module contract, persistence, the privacy surface, CI and release candidates keep full records: source identity, toolchain and runtime, input inventories and an audit entry. Title-owned gameplay, content and art changes need the PR's CI result plus a short PR note on what was exercised. Add an audit entry for those only when recording a failure, a decision or acceptance.

- `Packages/GameCore` contains renderer-independent domain interfaces and pure logic. It must not import title or renderer implementations.
- `Packages/GamePlatform` depends on `GameCore` and owns the reusable mobile shell/controller and Apple platform adapters. Its SwiftUI shell accepts title-provided renderer and gameplay views without importing a title.
- `Games/DevelopmentContent` is a local title-content package with original fixtures and one shared validation implementation for its app loader and command-line tool. It depends only on `GameCore`; neither foundation package imports it.
- `Games/<Title>` contains a title's entry point, module, rendering and `title.json` manifest; its rules and levels live in its own content package, such as `Games/BlockContent`. `Games/DevelopmentTitle` exercises the shared flow with an original practice scene, and `Games/BlockTitle` is the Block Match reference slice. A title imports the foundation and its own content only; `scripts/check-foundation.py` refuses another title's content. Start a new title with `scripts/new-title.py`; [Adding a title](docs/adding-a-title.md) lists what a title may rely on and how to evolve its content and the module contract.
- `experiments` contains disposable investigations outside production targets.

Keep each title's identity, assets, levels, bundle identifier and save namespace separate. Add tests for observable domain invariants and meaningful adapter behavior as features arrive; avoid tests that only repeat trivial implementation details. Inspect generated files in the same change as their generator inputs.

The [shell lifecycle decision](roadmap/decisions/ADR-004-mobile-shell-lifecycle.md) defines explicit resume, request identity and single-window ownership. [Local state](roadmap/decisions/ADR-005-local-save-durability.md) now makes production preferences durable; storage-free injected shell fixtures remain useful for pure lifecycle tests. Follow ADR-005 for persistence changes. Titles register through the [module contract version 1](roadmap/decisions/ADR-007-module-contract-v1.md) (`GameModule`, `ModuleSession` and `ModuleHost` in `GamePlatform`), which Spike 11 confirmed for a terrain title without change ([ADR-008](roadmap/decisions/ADR-008-dig-terrain-feasibility.md)). Use one `LocalSaveStore` actor per title namespace, outside the renderer-independent core. Filesystem access belongs in this reviewed adapter; writes carry a generation invalidated by destructive actions. Never downgrade future saves or silently overwrite corruption. App-hosted tests may inject storage, preparation and feedback; DEBUG-only UI launch arguments override large-text and reduced-motion presentation traits without replacing the production flow.

Follow the [bundled content guide](docs/bundled-content.md) for stable IDs, schema/content versions, deterministic input fixtures and manually shared playtest reports. Content order must never determine saved achievement identity. Removed IDs retain historical progress; materially changed achievements get new IDs. Input traces belong in developer fixtures, never production saves.

## Privacy, dependencies and content

Follow the [privacy contract](docs/privacy-contract.md). Apps work offline, with local saves/settings and no tracking, telemetry, accounts, ads or commerce. Review imports, packages, capabilities, entitlements, Info.plist and resources together; source scanning alone is insufficient.

Use original content and record its [provenance](docs/asset-provenance.md). Donpa and Leaves are design references only; GateEngine is declined for the starting foundation. No candidate's code, tests, translations, assets or tooling is approved for copying. The inventory separately reviews the small public-domain SplitMix64 formula adaptation; its notice ships with the development resources. Any future third-party inclusion needs a new review and an update to the [inclusion inventory](roadmap/audits/preflight-inclusion-bom.md) in the same change.

## License and contribution terms

The [MIT license](LICENSE) covers project-authored code, documentation and resources unless an explicit file or content record states otherwise. By submitting a contribution, you agree to provide it under those same terms and confirm that you have the rights to do so. Include the copyright and permission notice when redistributing copies or substantial portions.

Third-party material retains its own license, copyright and required notices. Record exact provenance and redistribution terms before inclusion; the repository's MIT license cannot override another rights holder's terms. Apple SDKs remain platform/toolchain inputs, not project-authored MIT content.
