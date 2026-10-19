# Epic 07 — Multi-title integration evidence

**Date:** 2026-10-19. **Status:** In progress.

## Scope so far

| Task | State |
| --- | --- |
| 1. Production `GameModule` contract, after closing ADR-006's open validation | Done: [ADR-006 validation](spike-06-module-seam.md#promoted-revision-validation-epic-07) passed on both geometries locally and hosted ([PR 20](https://github.com/1cf2ab6aafa31a3209ce70/1cf2ab6aafa31a3209ce70/pull/20)); [ADR-007](../decisions/ADR-007-module-contract-v1.md) records contract version 1 |
| 2. Second title target and the block reference slice | Not started |
| 3. New-title template or generator | Not started |
| 4. Contract tests with a fake module | Done with task 1 |
| 5. CI that scales with the number of titles | Not started |
| 6. Title-author documentation; contract published as provisional version 1 | ADR-007 records the contract; the author guide is not started |

## Module contract version 1

`GamePlatform` now exports `GameModule`, `ModuleSession`, `ModulePlayContext`, `ModuleHost` and, on iOS, `ModuleShellView`. [ADR-007](../decisions/ADR-007-module-contract-v1.md) maps the epic's title metadata, level decoding, rules factory, gameplay view factories and lifecycle callbacks onto them, and records the three changes from the experiment: identity and copy come from the module, play controls are title-owned with a lent pause action, and `ShellController` builds on the package's macOS test host.

The practice title registers through the contract. `PracticeModule` owns the SpriteKit scene and the play controls, `PracticeSession` validates the bundled catalog in `prepare(for:)` and records the synthetic `practice` progress, and `ShellModel` stays the composition root. Its copy, accessibility identifiers, save namespace and existing tests are unchanged.

`ModuleContractTests` run a fake module through the real `ShellController` and `LocalSaveStore` on the package host: launch, level load, pause and resume, foreground return, reduced motion, a success result, the save, and a relaunch that restores progress and settings. They also cover a recoverable load failure, refusal of an unsupported version before preparation, late and duplicate outcomes, settings delivery, another title's save namespace, and returning to the menu during loading.

Both seam studies now register through the production contract. Their first native run against it failed one app-hosted test: the promoted host checked the registration version once, at registration, while ADR-006's host checked it on every load, and the test changes a fake module's version between loads. The host now checks on every load. ADR-006's seam checks then passed against the production contract on both geometries.

## Validation

| Check | Revision and environment | Result |
| --- | --- | --- |
| `swift test` for `GamePlatform` | `f9118b4`, Xcode 27.1 (`27A9275`) | 38 tests passed, 7 of them contract tests |
| `scripts/verify.sh` | Contract changes before `f9118b4`, Xcode 27.1 | 34 core, 38 platform and 7 content tests; 11 CLI rejection cases; three builds |
| `scripts/test-mobile.sh` | Same, iOS Simulator 26.0 (`23A5287g`) | 22 app-hosted and 6 UI tests passed on each geometry, with no retry; both restart proofs passed |
| Seam verifier against the production contract | Clean `f9118b4`, Xcode 27.1, iOS Simulator 26.0 | 28 of 28 passed on iPhone 12 and iPad (9th generation), with no retry or runtime warning ([receipt](../../experiments/module-seam/evidence/contract-local-receipt.json)) |
| Same, hosted ([run 39269046205](https://github.com/1cf2ab6aafa31a3209ce70/1cf2ab6aafa31a3209ce70/actions/runs/39269046205)) | `96888f1` (`f9118b4` merged with the PR 20 docs), Xcode 26.6 (`17F113`), iOS Simulator 26.5 (`23F77`) | 28 of 28 passed, no retry or runtime warning, inputs unchanged, owned devices cleaned up ([receipt](../../experiments/module-seam/evidence/contract-hosted-receipt.json)) |

The pull request's hosted CI runs the full foundation matrix on the final revision.
