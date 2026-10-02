# Epic 04 — Local state and progression evidence

**Date:** 2026-10-02. **Status:** Complete for mobile simulator acceptance; updated hosted CI guard verified at `1c0945b9`.

## Implementation scope

[ADR-005](../decisions/ADR-005-local-save-durability.md) defines versioned Codable snapshots, title namespaces, explicit recovery and a previous-good backup. The small team separates shared models/storage, mobile shell/player controls and independent review. Production uses first-party Foundation and Swift concurrency; no database, remote dependency, cloud account, telemetry or import service is introduced.

The development practice exercises durable preferences and an original synthetic completion record. It does not implement the level pipeline or puzzle rules. Shared progress stores completion identifiers, best-score maxima and explicit title-provided unlocks. It does not infer currency, streaks or title rules.

## Verification

The full local acceptance run uses `daa53de16113a191b5d981967c0a9dcd7e1d9a10` with documentation-only changes; all 37 recorded inputs were independently checked byte-for-byte against that published revision. Subsequent test-only commit `86529b9f29b5a3eb0f5f07ac832b39d70d47b145` recognizes the hosted picker identifier and increases the full-suite time budget; it changes no production source. Focused native export cancellation passed on both local geometries at that commit; all 37 focused-run inputs match it. Historical hosted acceptance passed at that revision. The subsequent documentation closure did not change build/test inputs. The CI guard update below changes only the runner script; its successful hosted result is recorded separately below.

Local `bash scripts/verify.sh /private/tmp/gamecore-epic04-verification` passed 23 core tests and 31 platform tests, Debug/Release generic iOS Simulator builds and unsigned generic iOS Release compilation. Local Xcode is 27.0 (`27A266a`), Swift 6.4; the mobile runner uses iOS Simulator 26.0 (`23A5287g`). Generic iOS compilation is not a device run.

The storage tests exercise first/current snapshots, interrupted first and replacement writes, corrupt/missing current and backup, explicit recovery acknowledgment, old-schema migration once, unsupported/future schema with changed header shape, oversized primary/backup preservation, title collisions, duplicate/negative payload validation, reset backup clearing, generation invalidation, latest-preference preservation and I/O failure without defaults. Two core tests verify wire format and idempotent maxima/set-like progress.

Mobile app-hosted tests exercise controller relaunch, duplicate and stale completion callbacks, settings/result durability, title/language composition mismatch, recovery acknowledgment, unsupported-version blocking, reset/delete scope and backup attributes. Six UI methods exercise navigation, foreground pause/rotation, durable preferences/progress after process relaunch, large text/Reduce Motion, destructive cancellation/reset/deletion, and native export cancellation. The driver runs a separately prepared fixture before and after simulator shutdown/boot, verifies unchanged save bytes, then requires the restore test to read the expected settings/progress and remove its fixture.

Local raw evidence is retained under `/private/tmp/gamecore-epic04-verification` and `/private/tmp/gamecore-epic04-mobile-complete`, with focused alias regression under `/private/tmp/gamecore-epic04-export-alias`.

The [first hosted run](https://github.com/1cf2ab6aafa31a3209ce70/1cf2ab6aafa31a3209ce70/actions/runs/36964916687) passed package checks, builds and all 21 iPhone app/UI tests, then failed the restart driver because it retained a stale simulator data-container path. Xcode relocates that container between test invocations. The repair validates test-reported paths against the refreshed container and tracks the prepared fixture with a synthetic token. A focused iPhone shutdown/boot proof passed with unchanged save bytes and fixture cleanup. Final local verification passed all 21 app/UI tests per geometry with zero skips or runtime warnings, plus both shutdown/boot restore proofs and owned simulator cleanup.

The [second hosted run](https://github.com/1cf2ab6aafa31a3209ce70/1cf2ab6aafa31a3209ce70/actions/runs/36967672530) passed the 21 iPhone tests and restart proof, but failed iPad exporter cancellation before its full command exceeded 600 seconds. Its iPad sidebar identifier differs from the local runtime. The repair supports both observed identifiers and keeps the screenshot-confirmed close coordinate within the sidebar. That correction increased the full-suite budget to 900 seconds while keeping each case bounded at 120 seconds. These are the settings of the historical successful run, not the updated guard below.

The [historical successful hosted run](https://github.com/1cf2ab6aafa31a3209ce70/1cf2ab6aafa31a3209ce70/actions/runs/36970259860) passed at `86529b9`, with all 37 artifact input hashes matching the committed source. Xcode 26.6 (`17F113`) and iOS Simulator 26.5 (`23F77`) passed 54 package tests, all mobile build configurations, 21 app/UI tests per geometry and both shutdown/boot proofs. Both geometries have zero skipped tests or runtime warnings. All six selected restart invocations passed. Both owned simulators were shut down and deleted without cleanup warnings. The [retained manifest](epic-04-local-state-evidence.json) records exact inputs and local/hosted results. Hosted raw artifacts have the workflow's seven-day retention; the repository manifest persists independently.

## Hosted CI guard follow-up — 2026-10-02

The [documentation-tip run](https://github.com/1cf2ab6aafa31a3209ce70/1cf2ab6aafa31a3209ce70/actions/runs/36973904033), attempt 1 at `17190d66d692a6fbd5832387fae97f62e730ddaf`, failed the iPad case allowance. `testSettingsAndProgressPersistOnRelaunch` completed all assertions and was logged as passed after **129.949 seconds**, but Xcode's **120-second** per-case guard recorded a timeout/restart and listed the test as failed. This failed job is not successful hosted acceptance. Its iPhone suite and shutdown/boot proof passed before the iPad failure. One rerun of the unchanged inputs was started before this guard correction. Attempt 2 was cancelled after 35m7s when the new guard push superseded it through workflow concurrency; it supplies no acceptance result.

The narrow correction raises Xcode's per-case allowance to **180 seconds**, including selected restart invocations. It changes no production code or UI assertion. The full suite retains its **900-second** per-geometry cap, selected restart commands retain their 600-second caps, and the hosted job retains its **45-minute** cap. The aggregate suite bound does not promise that all cases can simultaneously consume their individual maximum. The separate guard commit and clean hosted run below identify and verify this update.

The original 37-input hash map remains historical evidence for `86529b9`. The guard changes `scripts/run-mobile-tests.py`; the other 36 recorded inputs remain unchanged. The manifest has a separate successful guard record with its exact revision, all 37 input hashes and base revision. It does not claim the changed script matches the historical successful run. No local native test run was repeated for this guard-only correction; the clean hosted guard run below supplies executed validation.

The updated [hosted CI guard run](https://github.com/1cf2ab6aafa31a3209ce70/1cf2ab6aafa31a3209ce70/actions/runs/36982386371) passed at `1c0945b9d9ea953bc7b8352368181115a5d4666a` in 37m40s. All 37 retained input hashes match that exact committed revision; only `scripts/run-mobile-tests.py` differs from the historical `86529b9` input map. Production code and UI assertions are unchanged. Xcode 26.6 (`17F113`) with iOS Simulator 26.5 (`23F77`) passed 54 package tests, all three mobile build configurations, 21 app/UI tests on each geometry and all six selected restart invocations. Both shutdown/boot proofs validated settings/progress, unchanged save bytes and fixture removal. Both owned simulators were shut down/deleted without cleanup warnings; both result summaries record zero failed/skipped tests or runtime warnings.

The iPad foreground/rotation case took 148.403 seconds and reset/delete took 121.176 seconds, demonstrating why the earlier 120-second case limit was insufficient. The updated 180-second allowance passed while the 900-second per-geometry, 600-second selected-restart and 45-minute job bounds remained unchanged. The original failing settings/progress case passed in 77.559 seconds on this run.

H01–H03 are closed by the separate exact guard revision/input map, executed bounded hosted success and retained historical evidence. Simulator and minimum-runtime/device limits remain unchanged.

## Acceptance coverage

| Requirement | Executed evidence and scope |
| --- | --- |
| Restore settings/progress after termination and reboot | App/controller relaunch and UI relaunch; shutdown/boot fixture proof on both simulator geometries |
| Interrupted writes retain valid prior or new state | Deterministic writer fault injection covers first writes and replacements; physical power loss is not certified |
| Known migration once; future saves preserved | Current/legacy/future/oversized fixtures and mobile recovery/blocking tests |
| Titles do not mix equal level IDs | Two title namespaces sharing one save root; separate standalone title targets remain Epic 07 work |
| No accounts, sync, currency, streaks or leaderboards by default | Model, package, capability and privacy-surface review; static checks are not an all-path runtime privacy certification |

## Review corrections

Independent review and executed tests resolved stale async controller acceptance after destructive changes, queued preference loss during reset, premature saved status, old-session completion, incompatible title/language composition, preservation of oversized/future saves, unclear storage errors, and virtualized Settings-row navigation in UI tests. The focused destructive flow passed in 84 seconds under the historical 120-second case guard. The later hosted allowance correction is recorded separately above; overall command bounds remain unchanged.

No remote dependency, app entitlement or Info.plist capability was added. The checked simulator bundle has no permission-description/background/ATS keys. Static review found no new directly listed required-reason API calls; FileManager size/protection attributes are confined to the reviewed adapter. These checks do not certify runtime all-path privacy or distribution declarations.

## Platform limits

Simulator termination/restart and filesystem fault injection establish software recovery in those environments. They do not certify physical reboot, flash/power-loss durability, hardware encryption or locked-device access. iOS 18 minimum-runtime and distribution checks remain explicit under [ADR-003](../decisions/ADR-003-simulator-mobile-foundation.md). The observed simulator reports backup exclusion but no file-protection metadata after accepting the protection request. Simulator builds tolerate only that absent-metadata case; wrong present metadata or setter failure still fails. Device builds require the expected complete-until-first-user-authentication class. When protection metadata is absent, the class comparison is unavailable; the app-hosted test records a capability-limit attachment and still checks backup exclusion without skipping the whole test. Physical devices are unavailable and macOS application work remains deferred.

## Player data controls

App-owned saves are excluded from OS backup to honor the local-only contract. Uninstall or device loss can destroy local progress. Deliberate native export creates a separate JSON copy in the player-selected Files provider; an external provider may transport that copy. The app does not sync, import or send it to the developer. Confirmed progress reset preserves preferences; confirmed local-data deletion removes preferences and owned recovery/staging files. Already exported copies remain under player control.

## Documentation review ledger

All entries are material because they affect implementation guidance or acceptance scope. Final disposition is checked against the documented behavior, source evidence and retained test results.

| Finding | Disposition | Evidence and verification |
| --- | --- | --- |
| F01: Session-only guidance conflicts with production persistence | Addressed | README, CONTRIBUTING, the Epic 02 historical baseline and ADR-004/005 distinguish durable production preferences from earlier/injected fixtures; changed sections reviewed together |
| F02: Reset, deletion and stale writes need distinct guarantees | Addressed | Player controls above and controller/storage tests cover preference preservation, namespace scope and generation invalidation |
| F03: Simulator attributes must not imply hardware encryption | Addressed | Platform limits above and ADR-005 state absent metadata, strict device behavior and physical-device limits |
| F04: Acceptance needs exact tested source identity | Addressed | Full local run at `daa53de`; focused local and clean hosted run at `86529b9`; all 37 inputs match their recorded revisions |
| F05: Restart and native-export harness failures need executed corrections | Addressed | Full local and hosted tests pass both geometries and restart proofs; focused native exporter alias regression also passes; failed-run causes retained above |
| F06: Exports and backup exclusion need clear player implications | Addressed | README, privacy contract and player controls above describe external providers, independent exports and device-loss scope |
| F07: Roadmap must reflect the completed gate and next dependency | Addressed | ROADMAP and Epic 04 record simulator acceptance and Epic 05 as next; physical/minimum-runtime limits remain explicit |
| F08: Failed-trial hashes must identify their own tested revision | Addressed | Evidence JSON labels the failed trial as `daa53de` and matches hashes to that recorded revision, separately from final `86529b9` |
| F09: An unavailable protection comparison must not imply executed coverage | Addressed | Platform limits explicitly distinguish absent class metadata from executed backup checks; the whole test is not skipped |

**Historical documentation readiness at `17190d6`:** Ready. Final coverage reviewed all changed sections and the acceptance table; F01–F09 are addressed, with no rejected, deferred, excluded or unresolved findings. Validation covers nine changed Markdown files and the evidence JSON: 94 local links resolve with no fragment targets, tracked/untracked whitespace checks pass, JSON parses, and all 37 historical final hashes match the tested `86529b9` commit. The follow-up guard intentionally changes one input and keeps its identity separate below. `git diff --check`, `git diff --cached --check` and `python3 scripts/generate-project.py --check` pass. CONTRIBUTING and the scripts expose no separate Markdown linter or documentation build. The three newly added hosted-run references were verified through GitHub run records/logs; the other 13 unchanged external references were not re-fetched. Physical-device, minimum-runtime and distribution limits remain as stated above.

### Follow-up documentation review

| Finding | Disposition | Evidence and verification |
| --- | --- | --- |
| H01: A passed assertion sequence exceeded the hosted case guard | Addressed | Attempt 1 logs record 129.949 seconds versus 120; the allowance is now 180 without changing UI assertions |
| H02: Individual allowances do not define the aggregate suite budget | Addressed | Runner comments and this follow-up retain 900 seconds per geometry and 45 minutes per job without claiming every case can use its maximum |
| H03: Changed guard inputs must not inherit the historical green result | Addressed | Original revisions/hashes and the successful run are retained; a separate exact guard revision, 37 matching input hashes and successful hosted result identify the new change |

**Follow-up documentation readiness:** Ready for review and commit. H01–H03 are closed by the verified hosted guard result and its separate input identity. The original F01–F09 ledger remains historical; all stated platform limits remain unchanged. All 3 local links in this changed document resolve, with no fragment targets; JSON parsing, retained input identity and whitespace checks pass. The new guard-run reference was verified through GitHub records/logs/artifacts; historical external references were not re-fetched for this follow-up.

## Current branch stabilization follow-up

The later documentation tip failed a shared UI assertion despite earlier successful acceptance. [The stabilization record](mobile-ui-stabilization.md) retains that failure, the evidence-backed helper corrections and eight passing focused executions. Independent per-geometry hosted checks are pending on the updated branch; historical hashes/results above remain unchanged.
