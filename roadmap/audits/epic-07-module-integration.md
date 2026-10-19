# Epic 07 — Multi-title integration evidence

**Date:** 2026-10-19. **Status:** In progress.

## Scope so far

| Task | State |
| --- | --- |
| 1. Production `GameModule` contract, after closing ADR-006's open validation | Done: [ADR-006 validation](spike-06-module-seam.md#promoted-revision-validation-epic-07) passed on both geometries locally and hosted ([PR 20](https://github.com/1cf2ab6aafa31a3209ce70/1cf2ab6aafa31a3209ce70/pull/20)); [ADR-007](../decisions/ADR-007-module-contract-v1.md) records contract version 1 |
| 2. Second title target and the block reference slice | Done: Block Match beside the practice title, with distinct bundle identifiers, icons, catalogs and save namespaces |
| 3. New-title template or generator | Done: `scripts/new-title.py` and `scripts/title-template` |
| 4. Contract tests with a fake module | Done with task 1 |
| 5. CI that scales with the number of titles | Done: titles come from manifests; pull requests test the titles they touch |
| 6. Title-author documentation; contract published as provisional version 1 | Done: [Adding a title](../../docs/adding-a-title.md) and ADR-007 |

## Module contract version 1

`GamePlatform` now exports `GameModule`, `ModuleSession`, `ModulePlayContext`, `ModuleHost` and, on iOS, `ModuleShellView`. [ADR-007](../decisions/ADR-007-module-contract-v1.md) maps the epic's title metadata, level decoding, rules factory, gameplay view factories and lifecycle callbacks onto them, and records the three changes from the experiment: identity and copy come from the module, play controls are title-owned with a lent pause action, and `ShellController` builds on the package's macOS test host.

The practice title registers through the contract. `PracticeModule` owns the SpriteKit scene and the play controls, `PracticeSession` validates the bundled catalog in `prepare(for:)` and records the synthetic `practice` progress, and `ShellModel` stays the composition root. Its copy, accessibility identifiers, save namespace and existing tests are unchanged.

`ModuleContractTests` run a fake module through the real `ShellController` and `LocalSaveStore` on the package host: launch, level load, pause and resume, foreground return, reduced motion, a success result, the save, and a relaunch that restores progress and settings. They also cover a recoverable load failure, refusal of an unsupported version before preparation, late and duplicate outcomes, settings delivery, another title's save namespace, and returning to the menu during loading.

Both seam studies now register through the production contract. Their first native run against it failed one app-hosted test: the promoted host checked the registration version once, at registration, while ADR-006's host checked it on every load, and the test changes a fake module's version between loads. The host now checks on every load. ADR-006's seam checks then passed against the production contract on both geometries.

## Titles from manifests

Each `Games/<Target>/title.json` names a title's app target, stable title ID, home-screen name, bundle identifier, content package and test directories. `scripts/titles.py` validates them, and the project generator, `check-foundation.py`, `verify.sh`, the mobile test runner and CI read titles only from there. Each app links the foundation and its own content product. The checks refuse an import of another title's content, and require the catalog `titleID` and the registered `TitleRegistration` ID to match the manifest. Changing a title's rules, art, levels or bundle metadata therefore touches only its own directories.

Xcode resolves every title's package in one graph, which refused two `ContentValidatorCLI` targets. Each content package's validator is now `<Content>Validator`.

## Block Match reference slice

`Games/BlockContent` holds two original boards and the slice's pure rules: select a group of two or more touching blocks of one color to clear it, and the blocks above fall into the gap. A board is won when empty and lost when no group remains; each clear of n blocks scores n × (n − 1). Validation rejects floating blocks and any board the bounded solver cannot clear. Replay fixtures reproduce the solution and a losing first choice on the second board. `Games/BlockTitle` registers `BlockModule` with a SpriteKit board and an accessible button per block that makes the same selection as a touch. Its session chooses the next board from saved progress, which the contract now delivers through `progressDidChange(_:)`. `TitleStorage` opens every title's store, including the DEBUG UI-automation namespace, so no title carries storage code.

The first UI run found that `LazyVGrid` creates block buttons only near the visible area, so an offscreen block had no control. The controls now use a plain grid.

## Scaffold, resources and lifecycle

`scripts/new-title.py` copies `scripts/title-template` into a skeletal title and regenerates the project. The skeleton includes the manifest, module, session, content package and validator, package, app-hosted and UI tests, a String Catalog, the privacy manifest and a placeholder icon rendered by `scripts/app-icon.py`. It builds and passes its tests before any gameplay, and no core source is copied. Both titles now have distinct original icons. Every title bundles exactly its asset catalog, `Localizable.xcstrings` and `PrivacyInfo.xcprivacy`, which `check-foundation.py` reviews. The manifest declares no tracking and no collected data, plus one required-reason API: the save store's `attributesOfItem` on its own files, reason `C617.1`.

`scripts/test-title-lifecycle.py` works on disposable copies. It removes each title in turn, then regenerates, checks, runs the core and platform tests, and builds the remaining title. It then scaffolds a third title, checks it, tests its content and builds it with its tests. CI runs it when the tooling, workflow or shared packages change.

## Validation

| Check | Revision and environment | Result |
| --- | --- | --- |
| `swift test` for `GamePlatform` | `f9118b4`, Xcode 27.1 (`27A9275`) | 38 tests passed, 7 of them contract tests |
| `scripts/verify.sh` | Contract changes before `f9118b4`, Xcode 27.1 | 34 core, 38 platform and 7 content tests; 11 CLI rejection cases; three builds |
| `scripts/test-mobile.sh` | Same, iOS Simulator 26.0 (`23A5287g`) | 22 app-hosted and 6 UI tests passed on each geometry, with no retry; both restart proofs passed |
| Seam verifier against the production contract | Clean `f9118b4`, Xcode 27.1, iOS Simulator 26.0 | 28 of 28 passed on iPhone 12 and iPad (9th generation), with no retry or runtime warning ([receipt](../../experiments/module-seam/evidence/contract-local-receipt.json)) |
| Same, hosted ([run 39269046205](https://github.com/1cf2ab6aafa31a3209ce70/1cf2ab6aafa31a3209ce70/actions/runs/39269046205)) | `96888f1` (`f9118b4` merged with the PR 20 docs), Xcode 26.6 (`17F113`), iOS Simulator 26.5 (`23F77`) | 28 of 28 passed, no retry or runtime warning, inputs unchanged, owned devices cleaned up ([receipt](../../experiments/module-seam/evidence/contract-hosted-receipt.json)) |

| `scripts/verify.sh` with both titles | `aef1447`, Xcode 27.1 | Core, platform and both content packages' tests; 11 CLI rejection cases; six builds |
| `scripts/test-mobile.sh`, both titles | `aef1447`, iOS Simulator 26.0 | Practice title 28 of 28 and Block Match 6 of 6 on each geometry, no retries; both restart proofs |
| `scripts/test-title-lifecycle.py` | Clean `8cf8c66`, Xcode 27.1 | Without Block Match, the practice title builds; without the practice title, Block Match builds; both with checks and core and platform tests; a scaffolded `ExampleTitle` passes its checks and content tests and builds with its tests |
| Scaffolded `ExampleTitle` on simulators | `0d80a41` plus `new-title.py`, iOS Simulator 26.0 | Its app-hosted test (load, pause gating, completion, save, relaunch) and UI test passed on iPhone 12 and iPad (9th generation) without edits |

Each pull request's hosted CI runs the foundation matrix on its final revision.
