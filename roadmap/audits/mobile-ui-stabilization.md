# Mobile UI stabilization and branch integration

**Date:** 2026-10-02. **Status:** Focused verification passed; current hosted verification pending.

## Scope

The follow-up fixes shared [UI test helpers](../../Tests/DevelopmentTitleUITests/DevelopmentTitleUITests.swift), resolves the Epic 04 contributor-guide conflict and runs hosted validation independently for each simulator geometry. Production app code, persisted data and time limits are unchanged. Existing behavior, geometry and progress checks are preserved; exporter dismissal proof is strengthened. Historical green runs remain historical; the failed documentation tips are retained below.

## Investigation and correction

[Epic 04 tip CI](https://github.com/1cf2ab6aafa31a3209ce70/1cf2ab6aafa31a3209ce70/actions/runs/36986968679) at `c028e85` passed package/build checks and 20 of 21 iPhone tests, then failed the rotation layout predicate. The 88.947-second case did not exceed its 180-second allowance. The recorded heading was fully onscreen. A redundant AX Window lookup consumed nearly the entire second layout wait before another heading evaluation. The helper now returns its verified window/heading snapshot; the test asserts positive bounds, requested orientation and full containment from that snapshot. A missing snapshot fails with geometry/hierarchy diagnostics. Foreground pause, explicit resume and completion assertions remain.

[Epic 05 tip CI](https://github.com/1cf2ab6aafa31a3209ce70/1cf2ab6aafa31a3209ce70/actions/runs/36987080334) at `d41c5d3` passed package/build checks and 22 of 23 iPhone tests, then failed Settings Done reachability after export cancellation. Video showed Files remained open, although the old navigation-bar absence check had passed. A broadly queried AX Cancel target produced an invalid automatic-scroll hit point.

Two focused trials refined the cause without weakening the assertion. The first assumed a leading X on both phone layouts; the accepted local iOS 26.0 recording instead showed an On My iPhone Back arrow. These are observed navigation states, not a promise that each runtime always opens the same directory. The second retained a positive-bounds Cancel Other, but its measured frame `(278,77,36,36)` exactly overlapped the native More button. Tapping its center opened view options. Thus bounds and a hittable flag alone did not establish cancellation semantics.

The reviewed correction selects genuine Cancel/Close buttons with positive visible bounds. Otherwise it uses the previously verified phone downward sheet gesture or the observed iPad sidebar X. It requires the native bars to disappear **and** Settings Done to exist and be hittable, then checks retained progress. The test never saves an export. Test-only diagnostics retain the target geometry and native hierarchy. Final reviewed UI SHA-256 is `5feea6ca8af0d3042f57ad632d4e5cad931f7159ddb7037a1fa93bf92ce1d215`.

The first focused trial passed rotation but failed cancellation; result finalization stalled and the owned command was interrupted with exit 130 after preserving the failure log. Owned simulator shutdown/delete succeeded. The second finalized with exit 1: rotation passed and cancellation failed on the misleading Other target; cleanup succeeded. Neither trial supplies export acceptance.

## Integration and CI

The sole merge conflict was [CONTRIBUTING](../../CONTRIBUTING.md)'s lifecycle paragraph. The resolution preserves durable production preferences, title-scoped storage and the explicitly provisional registration contract before Spike 06.

The [runner](../../scripts/run-mobile-tests.py) defaults to both geometries; `--model iphone12` or `--model ipad9` selects one and records `selectedModels`. Hosted jobs independently run full package/build verification, one complete app/UI suite and all selected restart invocations for their owned geometry. Matrix fail-fast is disabled and artifacts have distinct model names. Toolchain/action pins and the 180-second case, 900-second full suite, 600-second restart and 45-minute job limits are unchanged. Package checks repeat per job, so their sum is not a count of distinct tests.

## Review and verification ledger

All items are material because they govern accurate merge readiness or acceptance.

| ID | Finding | Disposition | Evidence / closure |
| --- | --- | --- | --- |
| U01 | Latest failed tips must remain visible | Addressed | Exact revisions, failures and historical distinction above |
| U02 | Native cancellation must hit the intended control and prove return | Focused verified; hosted pending | Frame/role evidence, strict Settings return and retained progress |
| U03 | Rotation must keep meaningful layout proof without redundant AX waits | Focused verified; hosted pending | Same measured geometry and explicit failure path |
| U04 | Observed native close/back layouts must not be conflated | Addressed in source | Failed trial retained; verified phone gesture and iPad close fallback |
| U05 | Corrected paths need focused repeats on both mobile geometries | Addressed | Eight executions passed, no skips/runtime warnings; 56 inputs match `76a1da7`; owned shutdown/delete verified |
| U06 | Current hosted checks need exact source identity on both branches | Pending | Independent model artifacts and package/build/UI/restart receipts |
| U07 | Serial CI has insufficient growth margin | Focused verified; hosted pending | Independent geometry jobs with unchanged coverage and bounds |
| U08 | Conflict resolution must preserve upstream module guidance | Addressed | Durable state and provisional Spike 06 wording retained |

Simulator results establish the tested software behavior only. Minimum-runtime, physical performance and distribution checks remain explicit under [ADR-003](../decisions/ADR-003-simulator-mobile-foundation.md); unavailable physical devices and macOS are not current development blockers. Spike 06 starts after this stabilization and PR 05 publication.

## Focused execution

The final reviewed source passed both selected methods twice on each iPhone 12/iPad (9th generation) geometry: eight executions, zero failures, skips or runtime warnings. Xcode 27.0 (`27A266a`) used iOS Simulator 26.0 (`23A5287g`). Both owned simulators were shut down and deleted. The recorded checkout was `133e870` with the final UI change uncommitted; all 56 captured inputs independently match committed `76a1da7a9a0b991af45c7340250ab45f2ed4283c`. The [manifest](mobile-ui-stabilization-evidence.json) retains both identities and the failed trials. This focused run does not replace full hosted acceptance.
