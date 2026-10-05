# Navigation contact-duration investigation

**Date:** 2026-10-04. **Status:** Local focused checks passed; hosted validation stopped at user request. PR 7 remains draft.

Two hosted failures retained a centered 50 ms XCTest tap without the expected shell transition. The trial changes only the shared UI-test helper to one native 150 ms press. It changes no production source, fixture selection, retries, scrolling, waits, assertions or timeout allowances. The existing existence/reachability and caller transition checks remain mandatory. A press request does not itself prove delivery or SwiftUI action entry.

## Failure evidence

| Run / checkout | Observation | Identity and retained evidence |
| --- | --- | --- |
| [PR 7 required run 37076170694](https://github.com/1cf2ab6aafa31a3209ce70/1cf2ab6aafa31a3209ce70/actions/runs/37076170694), actual merge checkout `e32f2cb5078142dbbe58cf835ba8a28ba3590010`, PR head `c9e9000e1ce1e8a12a5a0efe3cd88b61ee430fe4` | Navigation test's first Pause targeted `(195,607.6667)`, centered within `(24,574.7,342,66)`. The playing screen remained visible; `Missing heading shell.paused`. Case 91.430 s, below its 180 s cap. | Clean 58-input inventory matches PR-head bytes. The merge object was unavailable locally, so no independent merge-object comparison is claimed. Artifacts `/private/tmp/gamecore-pr7-navigation-evidence`; hierarchy and video `/private/tmp/gamecore-pr7-navigation-attachments`. |
| [Post-merge integration run 37074780990](https://github.com/1cf2ab6aafa31a3209ce70/1cf2ab6aafa31a3209ce70/actions/runs/37074780990), `a4b431aaf2f6d2cc921f796e4ead590c4894007c` | Large Text test's Resume targeted `(195,469)`, centered within `(24,434,342,70)`. The paused screen remained visible; `Missing control shell.complete`. 23/24 app/UI tests passed. UUID fixture setup succeeded; this was not the prior destructive-setup failure. | Clean 39-input inventory verified against the merge revision, earlier PR merge and head. Receipt/attachments `/private/tmp/gamecore-postmerge-integration-failure`. |

Both used Xcode 26.6 (`17F113`) and iOS Simulator 26.5. Video and AX establish the observed screen and advertised control location, not callback entry. Existing logs have no action journal to distinguish delivery/recognition failure from a later lifecycle/audio state reversal. No retained touch-rejection or hang record was found in the narrow console query; that absence is not proof that such events did not occur. Do not attribute the failures to an OS defect, hosted load or short-touch suppression without further evidence.

## Unchanged local baseline

At clean `c9e9000e1ce1e8a12a5a0efe3cd88b61ee430fe4`, the original input helper passed Navigation, Foreground/Rotation and Large Text on each iPhone 12 and iPad (9th generation): **six executions**, zero failures/skips/expected failures/runtime warnings. Xcode 27.0 (`27A266a`), iOS Simulator 26.0 (`23A5287g`). This toolchain/runtime differs from the failing hosted environment and does not supply changed-source acceptance.

Inventory: `/private/tmp/gamecore-navigation-baseline-20261004/inventory.json`; summaries `/private/tmp/navigation-baseline-iphone-summary.json` and `/private/tmp/navigation-baseline-ipad-summary.json`. Original UI-source SHA256: `2d5b467e4ca8c9f1f1dd977997bce1ee1ac421f16b98d23980a1f7fa97d9556c`.

## Controlled single-change trial

The shared helper at `Tests/DevelopmentTitleUITests/DevelopmentTitleUITests.swift` sends `button.press(forDuration: 0.15)` instead of its default tap, once per helper invocation. Existing direct native exporter/alert actions and scrolling gestures are unchanged. Independent review `/private/tmp/navigation-contact-review.md` accepts this as a narrow input hypothesis, not a demonstrated product correction. No action-entry instrumentation is enabled during the trial because it would alter timing and confound the single change.

| Evidence | Result |
| --- | --- |
| Changed-source local focus: `/private/tmp/gamecore-navigation-contact-20261004`; captured checkout `c9e9000…` with reviewed test change uncommitted, 58 inputs, Xcode 27.0/iOS 26.0 | Six executions passed: Navigation, Foreground/Rotation and Large Text on both geometries. Zero failures/skips/expected failures/runtime warnings; owned shutdown/delete succeeded. All 58 captured input bytes match code commit `a72a1645bcbbb7e9e21f5c8217606c4584e18d06`. |
| [Hosted run 37253122290](https://github.com/1cf2ab6aafa31a3209ce70/1cf2ab6aafa31a3209ce70/actions/runs/37253122290) on Xcode 26.6/iOS 26.5 | Code commit `a72a164`; canceled before acceptance completed at the user’s explicit request to stop tests. Duplicate push run 37253119779 was also canceled. No full hosted pass or current merge readiness is claimed. |

Captured changed UI-source SHA256: `b46bcaf9cc8315660606f8dd500ba0afd4c68cec65ac78728ccd78362a0a036d`. All 58 changed-source input hashes match committed `a72a164`; only this UI file differs from the unchanged baseline. A green unchanged baseline or historical CI run cannot replace current hosted acceptance.

If the trial fails, return to action-entry/state diagnostics before another targeting or product change. If it passes, record acceptance for the tested input and revision while leaving the original delivery/recognition mechanism explicitly unproven. Keep ordinary state, persistence, geometry and explicit-resume postconditions; do not retry activation or rerun until green as a substitute for evidence.

The [local evidence receipt](mobile-navigation-contact-evidence.json) preserves the 58 input hashes, per-model summaries and cleanup verification, separately from canceled hosted acceptance.

## Current disposition

**U10 remains open for hosted verification.** The reviewed input correction is committed and pushed; the underlying delivery/recognition mechanism remains unproven. Existing acceptance receipts describe earlier executions and do not validate this modified helper.

The local focused evidence covers six UI executions, not the complete app suite, package checks or simulator restart proofs. No further tests or prototype work were started after the user requested testing stop. Resume hosted acceptance only when testing is authorized again. The documentation follow-up uses GitHub’s commit-message skip directive to avoid starting another test run; workflow source and future normal validation triggers remain unchanged.
