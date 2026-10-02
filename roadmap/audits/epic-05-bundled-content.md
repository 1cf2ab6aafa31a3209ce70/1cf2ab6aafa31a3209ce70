# Epic 05 — Bundled content evidence

**Date:** 2026-10-02. **Status:** Complete for mobile simulator acceptance.

## Implementation and acceptance scope

The small team separates pure envelopes/deterministic boundaries, title-owned content/mobile integration and independent review. `GameCore` owns schema 1 catalogs and generic level envelopes, stable identity checks, the progress index, a fixed integer RNG and tick/input fixtures. `DevelopmentContent` owns the four original sample payloads, their bounded rule validators, packaged resource loader and command-line validator. The app and build tool use the same title validator. No foundation package depends on the title package.

The samples exercise block match, tile match, unscrew/panel and dig-the-ground without implementing the later complete games, rendering modules or solvability guarantees. The practice scene remains a lifecycle fixture. [The content guide](../../docs/bundled-content.md) defines authoring, stable-ID updates, developer replay boundaries and the manually shared playtest report.

The fixed SplitMix64 formula has a [narrow algorithm provenance review](preflight-inclusion-bom.md) and retained resource notice. Its pure UInt64 implementation and independently written bounded sampling add no external package or runtime service. All level layouts, payload fixtures and SVG resources are project-authored MIT material.

## Acceptance coverage

| Requirement | Executed evidence and scope |
| --- | --- |
| Invalid bundled content fails a clean build; one sample per planned type passes | 72 package tests, 11 CLI rejection cases, reviewer-executed clean native invalid-build gate and three valid build configurations |
| Same content/version/seed/input gives repeatable pure outcomes | Fixed RNG vectors independently checked in C; title reference inputs/outcomes repeat on host and both mobile geometries |
| Installed offline app enumerates and loads its levels | Installed resource reads and preparation in 23 app/UI tests per geometry, locally and hosted |
| Updating/reordering content retains unchanged completion | Core progress-index and persisted update fixtures pass locally/hosted; no positional remap or deletion |

## Validation

Full local validation uses `7c8cdea1678c9d5e7feeb98777f081e46454ce37`, with all 56 recorded inputs matching that commit. Subsequent `add88aa55db8e56f12364fab170ef78fbbbb293a` carries Epic 04’s reviewed test allowance from 120 to 180 seconds. Fifty-five inputs are unchanged; only the runner differs, with no app code, resource, assertion or package-test change. The final manifest identifies this difference rather than carrying earlier results onto a changed hash. Documentation edits are outside those inputs. The [evidence manifest](epic-05-bundled-content-evidence.json) retains the exact hashes, controlled invalid-build mutation and results.

`bash scripts/verify.sh /private/tmp/gamecore-epic05-verification-portable` passed 34 core, 31 platform and seven title-content tests (72 total), all 11 actual CLI rejection cases, Debug/Release generic iOS Simulator builds and unsigned generic iOS Release compilation. Each of the three built apps contains exactly the seven approved resource files with matching source hashes. Their Info.plist files have no permission-description, background-mode or ATS keys. Local Xcode is 27.0 (`27A266a`), Swift 6.4. Static checks and bundle inspection do not certify all runtime paths or distribution disclosures.

The reviewer executed a clean native build in a disposable filesystem copy with one invalid next-level reference. All 56 baseline input hashes match `7c8cdea`; the original files remained unchanged. Clean succeeded and build exited 65 at the shared validator, with no app executable produced. SwiftPM had already copied partial resource bundles, so this proof does not claim that no resource-copy work occurred. Separate CLI unknown-reference and unsupported-schema mutations each exited 1 with the expected error. Raw proof and logs are under `/private/tmp/gamecore-epic05-invalid-clean-build-portable`.

The initial implementation `363a8a5` passed 71 local package tests, its CLI cases and all builds, but [the first hosted run](https://github.com/1cf2ab6aafa31a3209ce70/1cf2ab6aafa31a3209ce70/actions/runs/36979532597) failed all six title-content tests before native builds. Xcode 26.6's host Foundation recognized the copied `Resources` directory as the resource root; appending `Resources` again produced a doubled path. The correction locates the catalog using Bundle resource lookup and selects it once. Real flat and Contents-style bundle fixtures also verify that malformed selected content cannot hide behind a valid alternate. The initial local simulator run was deliberately interrupted after that hosted failure; owned command and simulator cleanup completed, and it provides no acceptance claim.

Full local simulator acceptance at `7c8cdea` passed 23 app/UI tests per geometry on iOS 26.0 (`23A5287g`), with zero failures, skips or XCTest runtime warnings. Both shutdown/boot proofs restored the expected settings/progress with unchanged save bytes and removed their dedicated fixture. All six selected restart invocations passed, and owned simulator shutdown/deletion completed. Raw evidence is under `/private/tmp/gamecore-epic05-mobile-portable`.

[The next hosted run](https://github.com/1cf2ab6aafa31a3209ce70/1cf2ab6aafa31a3209ce70/actions/runs/36980343686) passed all 72 package tests and all builds, then recorded one timeout among 23 iPhone tests. The destructive-controls assertions completed successfully in 120.752 seconds; XCTest nevertheless failed the case for exceeding its 120-second allowance. The exact 56 input hashes match `7c8cdea`. Epic 04’s documentation-only tip independently showed an assertion-complete relaunch case at 129.949 seconds. The reviewed 180-second case allowance accommodates both observations while keeping the 900-second geometry command, 600-second restart command and 45-minute hosted job caps. Assertion failures still fail the suite.

[Final hosted validation](https://github.com/1cf2ab6aafa31a3209ce70/1cf2ab6aafa31a3209ce70/actions/runs/36982430110) passed at `add88aa`, with all 56 artifact input hashes matching that commit and the current source. Xcode 26.6 (`17F113`) and iOS Simulator 26.5 (`23F77`) passed all 72 package tests, 11 CLI rejection cases, three build configurations and 23 app/UI tests per geometry. All six selected restart invocations and both unchanged-save/fixture-removal proofs passed, with zero skips, runtime warnings or cleanup warnings. Owned simulators were shut down and deleted. The job finished in 42 minutes 8 seconds within its 45-minute cap. Raw downloaded evidence is under `/private/tmp/gamecore-epic05-hosted/final-run`; hosted artifacts have seven-day retention, while the repository manifest persists. Final closure changes documentation only and leaves these 56 inputs unchanged. Physical performance, iOS 18 minimum-runtime execution and distribution validation remain outside simulator acceptance under [ADR-003](../decisions/ADR-003-simulator-mobile-foundation.md). No physical device is required, and macOS application work remains deferred.

## Review and documentation ledger

Every item below is material because it affects implementation guidance or acceptance claims.

| ID | Finding | Disposition | Evidence and verification |
| --- | --- | --- | --- |
| F01 | Build and runtime validation must use the same rule implementation | Addressed | DevelopmentContent loader/CLI and native build phase |
| F02 | Updated content must preserve stable-ID achievements and historical records | Addressed | Core and persisted update fixtures; content guide policy |
| F03 | Reproduction needs fixed expected values across host and mobile | Addressed | Known RNG vectors and title fixture inputs/outcomes |
| F04 | Offline/privacy scope and trace/report boundaries need explicit guidance | Addressed | Installed resource reads, privacy checks and content guide |
| F05 | Algorithm adaptation needs provenance without claiming original algorithm authorship | Addressed | Three provenance documents re-read; local links/whitespace pass; upstream notice/digest verified, independent C golden vectors match Swift |
| F06 | Roadmap closure must match executed evidence and retain release limits | Addressed | Source manifest, build/mobile evidence and roadmap next gate |
| F07 | Resource inventory must exclude undeclared files and symlinks and require the promised notice | Addressed | CLI inventory, copied-directory baselines and negative packaging fixtures |
| F08 | Resource lookup must work on both observed SwiftPM/Foundation bundle layouts | Addressed | Hosted failure, portable Bundle resource lookup and layout fixtures |
| F09 | Hosted UI allowances must accommodate observed successful case durations | Addressed | Exact timeout results, unchanged assertions and separately scoped 180-second guard validation |

**Documentation readiness:** Ready. Independent review and final coverage checked all Epic 05 acceptance requirements and F01–F09; all nine findings are addressed, with none rejected, deferred, excluded or unresolved. The eight changed Markdown documents above the closure gate were re-read with their final sections; all 102 local links resolve, with no fragment targets. Tracked/staged/untracked whitespace checks, evidence JSON parsing and generated-project consistency pass. The 56 final input hashes match hosted `add88aa`; local and invalid-build records retain their distinct `7c8cdea` identity and runner difference. CONTRIBUTING and repository scripts expose no separate Markdown linter or documentation build. The three new hosted-run references were verified through GitHub records, logs and artifacts; the 13 unchanged external references in this documentation scope were not re-fetched. Simulator, minimum-runtime and distribution limits remain explicit.

**Next:** Spike 06; this epic's acceptance establishes its required content contract. It is a two-developer-day comparison of small grid and terrain modules against the accepted shell, saves and loader. It does not begin as part of Epic 05.

## Current branch stabilization follow-up

The later documentation tip failed a shared UI assertion despite earlier successful acceptance. [The stabilization record](mobile-ui-stabilization.md) retains that failure, the evidence-backed helper corrections and eight passing focused executions. Independent per-geometry hosted checks are pending on the updated branch; historical hashes/results above remain unchanged.
