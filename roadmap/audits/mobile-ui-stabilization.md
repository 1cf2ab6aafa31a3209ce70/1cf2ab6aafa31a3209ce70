# Mobile UI stabilization and branch integration

**Date:** 2026-10-02. **Status:** Verified; Epic 04 PR #6 merged.

## Scope

The follow-up fixes shared [UI test helpers](../../Tests/DevelopmentTitleUITests/DevelopmentTitleUITests.swift), resolves the Epic 04 contributor-guide conflict and runs hosted validation independently for each simulator geometry. The original helper corrections left production app code and persisted data unchanged. The follow-up adds a DEBUG-only UI automation storage-root selector in the title composition; Release continues to use the original root and save schema. Time limits remain unchanged. Existing behavior, geometry and progress checks are preserved; exporter dismissal proof is strengthened. Historical green runs remain historical; the failed documentation tips are retained below.

## Investigation and correction

[Epic 04 tip CI](https://github.com/1cf2ab6aafa31a3209ce70/1cf2ab6aafa31a3209ce70/actions/runs/36986968679) at `c028e85` passed package/build checks and 20 of 21 iPhone tests, then failed the rotation layout predicate. The 88.947-second case did not exceed its 180-second allowance. The recorded heading was fully onscreen. A redundant AX Window lookup consumed nearly the entire second layout wait before another heading evaluation. The helper now returns its verified window/heading snapshot; the test asserts positive bounds, requested orientation and full containment from that snapshot. A missing snapshot fails with geometry/hierarchy diagnostics. Foreground pause, explicit resume and completion assertions remain.

[Epic 05 tip CI](https://github.com/1cf2ab6aafa31a3209ce70/1cf2ab6aafa31a3209ce70/actions/runs/36987080334) at `d41c5d3` passed package/build checks and 22 of 23 iPhone tests, then failed Settings Done reachability after export cancellation. Video showed Files remained open, although the old navigation-bar absence check had passed. A broadly queried AX Cancel target produced an invalid automatic-scroll hit point.

Two focused trials refined the cause without weakening the assertion. The first assumed a leading X on both phone layouts; the accepted local iOS 26.0 recording instead showed an On My iPhone Back arrow. These are observed navigation states, not a promise that each runtime always opens the same directory. The second retained a positive-bounds Cancel Other, but its measured frame `(278,77,36,36)` exactly overlapped the native More button. Tapping its center opened view options. Thus bounds and a hittable flag alone did not establish cancellation semantics.

The reviewed correction selects genuine Cancel/Close buttons with positive visible bounds. Otherwise it uses the previously verified phone downward sheet gesture or the observed iPad sidebar X. It requires the native bars to disappear **and** Settings Done to exist and be hittable, then checks retained progress. The test never saves an export. Test-only diagnostics retain the target geometry and native hierarchy. The exporter/rotation correction before fixture isolation had reviewed UI SHA-256 `5feea6ca8af0d3042f57ad632d4e5cad931f7159ddb7037a1fa93bf92ce1d215`.

The first focused trial passed rotation but failed cancellation; result finalization stalled and the owned command was interrupted with exit 130 after preserving the failure log. Owned simulator shutdown/delete succeeded. The second finalized with exit 1: rotation passed and cancellation failed on the misleading Other target; cleanup succeeded. Neither trial supplies export acceptance.

## Integration and CI

The sole merge conflict was [CONTRIBUTING](../../CONTRIBUTING.md)'s lifecycle paragraph. The resolution preserves durable production preferences, title-scoped storage and the explicitly provisional registration contract before Spike 06.

The [runner](../../scripts/run-mobile-tests.py) defaults to both geometries; `--model iphone12` or `--model ipad9` selects one and records `selectedModels`. Hosted jobs independently run full package/build verification, one complete app/UI suite and all selected restart invocations for their owned geometry. Matrix fail-fast is disabled and artifacts have distinct model names. Toolchain/action pins and the 180-second case, 900-second full suite, 600-second restart and 45-minute job limits are unchanged. Package checks repeat per job, so their sum is not a count of distinct tests.

## Fixture isolation follow-up

The first matrix attempt was not acceptance for both branches. [Epic 04 matrix CI](https://github.com/1cf2ab6aafa31a3209ce70/1cf2ab6aafa31a3209ce70/actions/runs/37068515056) at `2dc6e7cf04556cd28c56e047692c66e4a4ad398a` passed both jobs' package checks and three build configurations. iPhone passed all 21 app/UI tests and three selected restart invocations. iPad passed 20 of 21 app/UI tests but failed `testLargeTextAndReducedMotionKeepControlsReachable` at the launch helper's confirmation tap, before its test body. Its restart proof was not run. Both owned simulators were shut down and deleted.

The recorded Delete tap point `(405,814)` lay inside the visible button frame `(135,788,540,52)`. No confirmation was visible in the retained late video frame or failure AX hierarchy. These observations establish unrelated destructive UI setup coupling; they do **not** establish whether action activation or SwiftUI alert presentation failed. The 99.225-second test did not exceed its 180-second allowance. An unchanged-source local baseline ran Foreground/rotation immediately before Large Text once on each geometry: four executions passed with zero failures, skips or runtime warnings and owned cleanup. Its 37 input hashes matched `2dc6e7c`; Xcode 27.0 (`27A266a`) and iOS Simulator 26.0 (`23A5287g`) did not reproduce the hosted Xcode 26.6/iOS 26.5 failure. That passing diagnostic baseline does not prove a latency or product cause.

Separately, [Epic 05 matrix CI](https://github.com/1cf2ab6aafa31a3209ce70/1cf2ab6aafa31a3209ce70/actions/runs/37068521038) at `abd0c01d2997a66c275414c921ea2e1f92a18f45` was verified green: 72 distinct package checks and 11 CLI rejection cases per job, all three builds per job, 23 app/UI tests per geometry, six selected restart invocations, both byte-preservation/removal proofs, zero failures/skips/runtime warnings and owned cleanup. All 56 artifact inputs matched both its head and `76a1da7`. This is pre-isolation evidence; it does not supply acceptance for the new fixture selector.

Each UI test now supplies one fresh `--ui-test-fixture` UUID at its initial launch. A DEBUG-only [title helper](../../Games/DevelopmentTitle/ShellUITestFixture.swift) validates the identity and derives `GameCoreSaves/UIAutomationFixtures/<canonical UUID>` beneath the existing Application Support root; LocalSaveStore appends the unchanged `development-practice` title namespace. It accepts no arbitrary paths or deletion commands. Missing fixture values, malformed values or duplicate flags fail closed before store construction; no argument selects the original root. Release excludes the helper and always selects that original root, even if launch arguments are present. The same application object retains its UUID across terminate/relaunch to exercise real local persistence. Owned disposable simulator cleanup removes the fixture containers.

Only the launch helper's unrelated Settings/Delete precondition was removed. The dedicated reset/delete/cancel UI test retains its destructive operations, preference/progress checks and cancellation postconditions. Exporter and rotation assertions are unchanged by this follow-up. The same production actor, schema, flow and feedback services serve the fixture namespace.

Three new [app-hosted test methods](../../Tests/DevelopmentTitleTests/UITestFixtureTests.swift) cover the unchanged default path, canonical/lowercase UUID handling and pure parsing without directory creation; nine missing/empty/malformed/path/duplicate argument vectors; same-UUID relaunch persistence, different-UUID initial isolation plus save/delete, preservation of the first fixture, and unchanged default `save.json`/`save.previous.json` bytes after invalid arguments and fixture operations. The reviewed test SHA-256 is `510a8080ec57d1c0b7e3d75729ca481fe6973fbb3640c3bfae188d3bec1aacf7`. The final local run executed all three methods and the complete 26-test app/UI suite on each geometry, plus all six selected restart invocations and both byte-preservation/fixture-removal proofs. All 58 input hashes match committed `ab613a84`; owned shutdown/delete passed and both simulator UUIDs were independently absent. Package checks (72), CLI rejection cases (11) and all three mobile builds passed. The Release app binary contains no fixture-selector literal; the Debug app retains it in its debug dylib, consistent with the reviewed compilation guards.

### Verified current acceptance

Both final matrices completed successfully under Xcode 26.6 (`17F113`) and iOS Simulator 26.5 (`23F77`). Each artifact records one selected geometry and clean source. All hashes match the published branch head and expected input manifest; Epic 04 also matches its actual PR merge checkout `9e01b5b`.

| Branch | Verified source / run | Completed evidence |
| --- | --- | --- |
| Epic 04 | `5412491cef1fcb30ab6a6c4e62a568ed676ed954`; [37071968298](https://github.com/1cf2ab6aafa31a3209ce70/1cf2ab6aafa31a3209ce70/actions/runs/37071968298) | 39 matching inputs; 54 distinct package checks and all three builds per job; 24 app/UI tests per geometry; six selected restart invocations, both preservation/removal proofs and owned cleanup |
| Epic 05 | `ab613a840f03cf7f43928b142ae7ac17566ff5c8`; [37071987418](https://github.com/1cf2ab6aafa31a3209ce70/1cf2ab6aafa31a3209ce70/actions/runs/37071987418) | 58 matching inputs; 72 distinct package checks, 11 CLI rejection cases and all three builds per job; 26 app/UI tests per geometry; six selected restart invocations, both preservation/removal proofs and owned cleanup |

Both runs have zero failures, skips, expected failures or runtime warnings. All three new fixture-isolation methods ran on each geometry. The longest jobs were 28m21s for Epic 04 and 20m37s for Epic 05, within the unchanged 45-minute bound. The [evidence manifest](mobile-ui-stabilization-evidence.json) preserves separate failed, diagnostic-baseline, pre-isolation and final identities.

[Epic 04 PR #6](https://github.com/1cf2ab6aafa31a3209ce70/1cf2ab6aafa31a3209ce70/pull/6) merged as `a4b431aaf2f6d2cc921f796e4ead590c4894007c`; its full tree equals the verified PR checkout. Epic 05's integration merge and final acceptance documentation change no inventoried input bytes. Automatic checks on later documentation/PR revisions are distinct from these verified execution receipts.

## Review and verification ledger

All items are material because they govern accurate merge readiness or acceptance.

| ID | Finding | Disposition | Evidence / closure |
| --- | --- | --- | --- |
| U01 | Latest failed tips must remain visible | Addressed | Original failed tips and first matrix failure retained separately from green evidence |
| U02 | Native cancellation must hit the intended control and prove return | Addressed | Frame/role evidence, strict Settings return and retained progress |
| U03 | Rotation must keep meaningful layout proof without redundant AX waits | Addressed | Same measured geometry and explicit failure path |
| U04 | Observed native close/back layouts must not be conflated | Addressed in source | Failed trial retained; verified phone gesture and iPad close fallback |
| U05 | Corrected paths need focused repeats on both mobile geometries | Addressed | Eight executions passed, no skips/runtime warnings; 56 inputs match `76a1da7`; owned shutdown/delete verified |
| U06 | Current hosted checks need exact source identity on both branches | Addressed | Both final model artifacts verified against exact branch/checkout identities; all package/build/UI/restart receipts complete |
| U07 | Serial CI has insufficient growth margin | Addressed | Independent geometry jobs with unchanged coverage and bounds |
| U08 | Conflict resolution must preserve upstream module guidance | Addressed | Durable state and provisional Spike 06 wording retained |
| U09 | Unrelated destructive setup can prevent another test from reaching its acceptance body | Addressed | Validated DEBUG UUID isolation removes only setup deletion; dedicated destructive coverage retained; actual activation-versus-presentation cause remains unproven |

Simulator results establish the tested software behavior only. Minimum-runtime, physical performance and distribution checks remain explicit under [ADR-003](../decisions/ADR-003-simulator-mobile-foundation.md); unavailable physical devices and macOS are not current development blockers. Next is Epic 05 review and Spike 06; new prototype work was kept out of this testing/merge wrap-up.

## Historical focused execution

The final reviewed source passed both selected methods twice on each iPhone 12/iPad (9th generation) geometry: eight executions, zero failures, skips or runtime warnings. Xcode 27.0 (`27A266a`) used iOS Simulator 26.0 (`23A5287g`). Both owned simulators were shut down and deleted. The recorded checkout was `133e870` with the final UI change uncommitted; all 56 captured inputs independently match committed `76a1da7a9a0b991af45c7340250ab45f2ed4283c`. The [manifest](mobile-ui-stabilization-evidence.json) retains both identities and the failed trials. This focused run does not replace full hosted acceptance.


## Final documentation review

Ready. Final coverage checked U01–U09 against the corrected source, executed tests, historical distinctions and current receipts; all nine are addressed. The activation-versus-presentation cause of the earlier setup failure remains unproven and is not claimed as repaired. Fixture isolation removes its unrelated setup dependency while dedicated destructive UI acceptance remains executed.

Validation covers this record, the two epic audits' current follow-up sections and the evidence JSON: final sections re-read, all 17 local links across the three changed Markdown files resolved (no fragment targets), JSON parsed, whitespace and generated-project consistency checked, and all 58 current Epic 05 input bytes matched the verified hosted manifest. CONTRIBUTING and repository scripts expose no separate Markdown linter or documentation build. New run/merge references were verified through GitHub metadata, logs and artifacts; unchanged historical references in the epic audits were not re-fetched. Simulator, minimum-runtime and distribution limits remain explicit.
