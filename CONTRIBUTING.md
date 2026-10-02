# Contributing

This repository contains an original mobile foundation, a playable lifecycle shell and a separate [disposable platform experiment](experiments/platform-baseline/README.md). Puzzle rules, levels, durable saves and complete titles remain roadmap work.

## Start here

Read the [roadmap](ROADMAP.md), [first-party foundation decision](roadmap/decisions/ADR-001-first-party-foundation.md), and [mobile simulator acceptance policy](roadmap/decisions/ADR-003-simulator-mobile-foundation.md). Current production targets are iOS/iPadOS 18.0 and later. Use simulators with iPhone 12 and iPad (9th generation) screen geometry; no physical device is required for this work. macOS development and release are deferred.

The configured CI baseline is the `macos-26` runner with Xcode 26.6 (`17F113`) and iOS 26.5 simulator runtime. Xcode 27.0 (`27A266a`) with Swift 6.4 and the iOS 26.0 simulator runtime is the observed local environment. Packages and targets use Swift 5 language mode. Keep recorded results tied to the actual toolchain/runtime: a local pass does not mean the configured remote workflow has run.

Use Python 3.9 or newer for the standard-library project/check/test scripts. From the repository root:

```sh
bash scripts/verify.sh
bash scripts/test-mobile.sh
```

The first command checks generated-project consistency and architecture/privacy boundaries, runs core and platform logic tests, and builds Debug/Release for a generic simulator plus unsigned Release for generic iOS. The second runs app-hosted model and UI tests on the two selected simulator geometries. Open `GameCore.xcworkspace` with scheme `DevelopmentTitle`. Follow the [root README](README.md) for project generation, simulator selection and exact tool requirements. Tests cover meaningful transitions, preparation, feedback lifetime and user-facing shell paths. These checks do not certify a complete game, physical performance, runtime privacy or minimum-OS execution.

The disposable experiment has its own build/test commands in its README. Its renderer integration evidence does not make the experiment a production package or title.

## Changes and ownership

Keep changes focused and explain the behavior or decision they change. Include relevant validation and remaining uncertainty. Preserve the roadmap's dependencies unless an explicit decision revises them. Simulator results must be labeled with runtime and geometry; a deployment-target build is not execution on the minimum OS.

- `Packages/GameCore` contains renderer-independent domain interfaces and pure logic. It must not import title or renderer implementations.
- `Packages/GamePlatform` depends on `GameCore` and owns the reusable mobile shell/controller and Apple platform adapters. Its SwiftUI shell accepts title-provided renderer and gameplay views without importing a title.
- `Games/<Title>` contains a title's entry point, rules, rendering and bundled content. `Games/DevelopmentTitle` exercises the shared flow with an original practice scene.
- `experiments` contains disposable investigations outside production targets.

Keep each title's identity, assets, levels, bundle identifier and future save namespace separate. Add tests for observable domain invariants and meaningful adapter behavior as features arrive; avoid tests that only repeat trivial implementation details. Inspect generated files in the same change as their generator inputs.

The [shell lifecycle decision](roadmap/decisions/ADR-004-mobile-shell-lifecycle.md) defines explicit resume, request identity, single-window ownership and session-only settings. Implement persistence only within Epic 04 under [ADR-005](roadmap/decisions/ADR-005-local-save-durability.md) or treat this small registration type as the final game-module contract. App-hosted tests may inject preparation and feedback; DEBUG-only UI launch arguments override large-text and reduced-motion presentation traits without replacing the production flow.

## Privacy, dependencies and content

Follow the [privacy contract](docs/privacy-contract.md). Apps work offline, with local saves/settings and no tracking, telemetry, accounts, ads or commerce. Review imports, packages, capabilities, entitlements, Info.plist and resources together; source scanning alone is insufficient.

Use original content and record its [provenance](docs/asset-provenance.md). Donpa and Leaves are design references only; GateEngine is declined for the starting foundation. No candidate's code, tests, translations, assets or tooling is approved for copying. Any future third-party inclusion needs a new review and an update to the [inclusion inventory](roadmap/audits/preflight-inclusion-bom.md) in the same change.

## License and contribution terms

The [MIT license](LICENSE) covers project-authored code, documentation and resources unless an explicit file or content record states otherwise. By submitting a contribution, you agree to provide it under those same terms and confirm that you have the rights to do so. Include the copyright and permission notice when redistributing copies or substantial portions.

Third-party material retains its own license, copyright and required notices. Record exact provenance and redistribution terms before inclusion; the repository's MIT license cannot override another rights holder's terms. Apple SDKs remain platform/toolchain inputs, not project-authored MIT content.
