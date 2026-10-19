# Spike 06 — module-seam evidence

**Date:** 2026-10-04. **Status:** Complete within the timebox and focused simulator scope; experiment decision accepted.

PR #7 was merged by explicit user instruction at `cb11d713f0641d47bd59b85fe64dbe4401d70486`. Its navigation contact change subsequently passed complete hosted checks, but a later same-input iPhone Resume failure required the separate [U10 investigation](mobile-navigation-contact.md). Current full hosted acceptance subsequently passed exact `0b85d51` on both geometries, closing U10 for that revision. The scoped DEBUG diagnostic run passed six navigation cases and does not prove the cause of earlier failures. These foundation checks remain separate from this spike’s focused experiment evidence.

The [experiment](../../experiments/module-seam/README.md) and [ADR-006](../decisions/ADR-006-game-module-seam.md) compare existing closure registration with a narrow associated-view/session protocol. The protocol uses the existing shell, feedback and save services. Original SpriteKit block and non-AR RealityKit terrain studies retain their own renderers and hit testing. Shared production packages and the production app are unchanged. Both targets use the original development catalog in separate app containers; independent production-title catalogs remain Epic 07 work.

## Review dispositions

| Finding | Materiality | Disposition and evidence | Verification |
| --- | --- | --- | --- |
| S06-01 — concrete simulation required by registration | Material: would constrain title-owned rules | Addressed: associated `Session: ModuleSession`; protocol has no DevelopmentContent or renderer types | Static review and independent-session test |
| S06-02 — initial preferences delivered twice | Material: callbacks could duplicate side effects | Addressed: Published subscription supplies the initial value; equality removes later duplicates | Initial/change setter-count assertions |
| S06-03 — malformed fixture silently uses normal storage | Material: invalid test identity could write ordinary local data | Addressed: explicit flags require one valid UUID; canonical derived path; errors preserve data | Malformed/missing/duplicate parser assertions |
| S06-04 — result may precede durable save | Material: relaunch evidence could race persistence | Addressed: native smoke awaits saved status before terminating | UI result/save/relaunch assertions |
| S06-05 — project restoration could skip owned-device cleanup | Material: shared host resources could remain occupied | Addressed: restoration and shutdown/deletion are independent guarded operations | Focused verifier receipt and cleanup logs |
| S06-06 — verification could accept omitted tests | Material: exit code alone does not establish coverage | Addressed: summaries require seven passing tests; final verifier also rejects runtime warnings and expected failures | Actual summaries and mocked skipped-test refusal |
| S06-07 — broad acceptance claims from one simulator | Material: would overstate mobile coverage | Addressed: evidence scoped to one geometry/runtime, Debug builds and tiny samples | README, ADR and this audit limits |
| S06-08 — hashes captured only after execution | Material: would overstate compiled source provenance | Addressed: receipt explicitly states post-run timing; final verifier captures/compares dependency and experiment inputs before/after execution | Original hashes match the recorded code commit; review receipt matches final compiled inputs before/after; final verifier metadata changes were reviewed without a full native rerun |
| S06-09 — cleanup error could return exit zero | Material: executable result could conceal leaked resources | Addressed: final verifier exits nonzero for restoration/cleanup failures | Mocked restoration and boot failures both attempted shutdown/delete and failed |

| S06-10 — cancelled preparation can erase a newer stage before checking cancellation | Material: a current load could fail or begin without its prepared state | Addressed: check cancellation before changing epoch/staged state; extend the existing race regression | One final-code targeted case passed; compiled input hashes matched before/after |

## Execution scope

Focused serial verification builds each target with the other renderer removed from the generated project, runs six app-hosted tests and one native renderer-input/relaunch test per target, and restores the two-target project. One owned iPhone 12 simulator is used; builds have two jobs and one architecture. No foundation matrix, package-suite repetition, physical device, macOS work or performance benchmark is included.

The app-hosted tests check validated identity and deterministic inputs for both samples, input gates, preparation races, version refusal, late and duplicate outcomes, settings, reduced motion, failure without progress, exact selected-level saves, restore and deletion. The native tests exercise SpriteKit touch and RealityKit entity hit conversion, finish through accessible controls and confirm persisted progress after relaunch.

An initial project build exposed an Xcode target-order dependency cycle; using dependency-order scheme scheduling fixed it. An initial verifier invocation rejected an unsupported suite-timeout option before executing any test case; the option was removed and its owned simulator was shut down/deleted. These attempts are not passing acceptance evidence.

## Results and validation limits

The [focused receipt](../../experiments/module-seam/evidence/focused-receipt.json) records the initial **14 passing tests**: seven in each independently built target, zero failures/skips/expected failures/runtime warnings. Native SpriteKit touch removed the expected first block; RealityKit's actual entity hit completed the dig sample. Both UI tests waited for durable save status and restored completion after relaunch. App-hosted tests verified the exact saved stable IDs. Xcode 27.0/27A266a and iOS 26.0/23A5287g were used on one owned iPhone 12. Project restoration, shutdown and deletion all exited zero; the owned UUID was independently confirmed absent afterward.

The executed verifier recorded source hashes after testing. Swift inputs were frozen throughout the initial run and matched its original recorded commit; this is not a before/after provenance guarantee. The final verifier now compares experiment and dependency inputs before and after execution, refuses warning/expected-failure summaries, and returns failure when cleanup fails. Prototype code was committed as `b60fec4`, and final verification tooling as `4ee7e9e`; recorded app/test hashes match those committed files. Four mocked command-orchestration checks passed (success, restoration failure, boot failure and skipped-test rejection), with no additional native runs. The final verifier's orchestration has not been rerun natively; its changed metadata gates do not alter compiled application or test code.

A final review identified S06-10: already-cancelled preparation mutated its epoch and cleared a current staged load before checking cancellation. The guard now runs before any mutation. The existing superseded-preparation test asserts that the cancelled loader never enters and the current staged session survives. The [review regression receipt](../../experiments/module-seam/evidence/review-regression-receipt.json) records one passing targeted test, zero failures/skips/expected failures/runtime warnings, matching compiled-input hashes before/after, and successful owned iPhone 12 shutdown/deletion. No other native tests were run during this review; the fourteen original tests were not repeated after this fix.

No iPad, Release/unsigned-device build, minimum iOS 18 runtime, performance or hosted acceptance was run. The two apps remain renderer/rule samples, not complete titles. These limits are explicit future integration checks, not missing spike prototype features.

## Promoted-revision validation (Epic 07)

[Epic 07](../epics/07-module-integration.md) first closes this spike's open native validation, on the sources promoted to the integration branch. The verifier now runs each target on an owned iPhone 12 and then an owned iPad (9th generation), one simulator at a time. It honors `GAMECORE_SIM_RUNTIME_VERSION` like the foundation collector. It retries a failed case once and names every retry in its receipt, classifying it with the collector's scan for the simulator input fault behind N06, because the result summary reports a retried case as passed. A timed-out command now stays in the receipt. The Mobile validation workflow runs the verifier when dispatched with `module_seam`. Seven mocked orchestration cases cover passing, a retried pass, project-restoration failure, boot failure, a skipped test, a test timeout and a missing pinned runtime.

Three problems surfaced before the accepted runs. An early local iPad run passed all seven grid tests, but its `xcodebuild` did not exit within the 600-second limit; later runs, including both accepted runs, did not repeat it. A later local run failed the summary gate on one iPad runtime warning: on iOS 26 an app without upside-down portrait reports that support for all orientations will soon be required. The experiment apps now declare all four iPad orientations, as the production app already does. The first hosted dispatch failed in the mocked checks, which inherited the job's pinned runtime; the harness now clears it.

| Run | Toolchain and runtime | Result |
| --- | --- | --- |
| [Local receipt](../../experiments/module-seam/evidence/promoted-local-receipt.json), clean `284dc23` | Xcode 27.1 (`27A9275`), iOS Simulator 26.0 (`23A5287g`) | 28 of 28 passed (7 per target per geometry); no failure, skip, expected failure, runtime warning or retry; 41 inputs unchanged; owned devices shut down and deleted |
| [Hosted run 39264608310](https://github.com/1cf2ab6aafa31a3209ce70/1cf2ab6aafa31a3209ce70/actions/runs/39264608310) ([receipt](../../experiments/module-seam/evidence/promoted-hosted-receipt.json)), `284dc23` | Xcode 26.6 (`17F113`), iOS Simulator 26.5 (`23F77`) | Same: 28 of 28 passed with no failure, skip, expected failure, runtime warning or retry; inputs unchanged; owned devices shut down and deleted. Commands took about 17 minutes, including two 110–130-second boots |

This closes the iPad and hosted-acceptance limits above for these focused checks. Release builds, the iOS 18 minimum runtime and performance remain outside the seam evidence; the foundation matrix covers the production app.

## Decision boundary and next step

A shared renderer abstraction offers no demonstrated reduction here: nodes, entities, hit conversion and geometry stay module-owned. The compile-time registration groups shell callbacks while leaving simulations and concrete views independent. Promote only the demonstrated seam during [Epic 07](../epics/07-module-integration.md), with original per-title catalogs and save namespaces. Complete the broader iPad, release and minimum-runtime checks as part of that integration rather than extending this spike into full games.

Documentation finalization: all ten material review findings are addressed. Changed sections were re-read against the source, executed summaries and stated limits. All local links in the five changed Markdown documents resolved; no new external links were introduced. Contributor guidance and repository scripts define no Markdown linter or documentation build. Whitespace checks, script syntax, generated-project currency and evidence JSON validation passed. The entry-cancellation guard and extended race assertion were subsequently verified by one targeted final-code test; the original fourteen-test run is retained as historical evidence.

The branch commits skip the unrelated foundation CI matrix; hosted verification was not scheduled for this experiment. The repository workflow is unchanged.
