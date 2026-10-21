# Epic 08 — Quality and release baseline evidence

**Date:** 2026-10-20. **Status:** Not complete. Every automated gate, its seeded-violation self-test, the network observation, the regression baselines, the release checklist, the hardware check and ADR-009 are in place, and the reference title passes every automated check on both simulator geometries locally. Two things remain open. Three interactive steps of the accessibility checklist have not run: Accessibility Inspector headings and focus, Full Keyboard Access, and the Grayscale color filter. Hosted CI has not run this change, including the iOS 18.0 minimum-runtime job ([acceptance](#acceptance)).

Every number here is a simulator observation or a property of a built bundle. None is a device result or a physical budget ([ADR-003](../decisions/ADR-003-simulator-mobile-foundation.md), [ADR-009](../decisions/ADR-009-release-scope-without-hardware.md)).

## Source identity

| Item | Value |
| --- | --- |
| Base revision | `b0276d8b2326692e7b3e69b69e22eb02d93a411e` (Spike 11 branch head); branch `wip/epic-08-release-baseline` |
| Working tree | Dirty when the runs below were made: the Epic 08 changes were uncommitted. They were then committed unchanged as `80c876f`..`cdb2a8f`; the 142 inputs at `8ccc728` and later hash identically to the recorded ones |
| Inputs | 142 files under `Packages`, `Games`, `Tests`, `GameCore.xcodeproj`, `GameCore.xcworkspace`, `scripts` and `.github`; aggregate SHA-256 `366cb4f767433f284c7d0356f504bf17895f18d3ab0549b43b4054d1902f5502`. The per-file hashes are in the [evidence file](epic-08-release-baseline-evidence.json) |
| Same inputs for | `verify.sh`, `test-mobile.sh` and `record-baselines.py`: the mobile run's inventory and the recorder's source identity carry identical hashes, and no input changed between `verify.sh` and them. Documentation outside those directories changed afterwards |

## Toolchain, runtime and host

| Item | Value |
| --- | --- |
| Xcode | 27.1 (`27A9275`), iOS 27.1 SDK, Swift 6.4 compiler in Swift 5 language mode |
| Simulator runtime | iOS 26.0 (`23A5287g`); no iOS 18 runtime is installed locally |
| Geometries | iPhone 12 and iPad (9th generation), owned simulators named `GameCore Mobile <model> integrator <id>`, created and deleted per run; none left afterwards |
| Host | Mac14,6 (Apple M2 Max, 12 logical CPUs, 32 GiB), macOS 27.2. Not quiet: a virtual machine, Spotlight indexing and other sessions shared it; load averages are recorded with each run |
| CI baseline (not run) | `macos-26`, Xcode 26.6 (`17F113`), iOS 26.5; the minimum-runtime job pins iOS 18.0 |

## Gates

Each gate runs in CI on every title the manifests list, and each first runs a self-test that fails unless the gate refuses seeded violations. `verify.sh` runs in the `verify` job on every push and pull request; `test-mobile.sh` runs in the `foundation` matrix (title × geometry) and the `minimum-runtime` matrix (geometry, every title).

| Gate | Where it runs | Seeded-violation self-test | Reference title | Practice title |
| --- | --- | --- | --- | --- |
| Static privacy surface, `check-foundation.py` (now reading the shared lists in `release_policy.py`) | `verify.sh` | `test-foundation-check.py` on a repository copy refuses `import WebKit`, `import FirebaseAnalytics`, `registerForRemoteNotifications`, a URL scheme in a title Info.plist and `SKAdNetworkItems` in a package plist | Pass | Pass |
| Required-reason APIs, `check-required-reason-apis.py` | `verify.sh`, per Release iOS app | `test-required-reason-check.py` (Epic 07) | None referenced | None referenced |
| Bundle audit, `check-app-bundle.py`: linked libraries against an allowlist, embedded code, entitlements, Info.plist keys, privacy manifest | `verify.sh`, per Release iOS app | `test-app-bundle-check.py`: clean unsigned and ad-hoc signed bundles pass; refuses push and iCloud entitlements, an embedded `@rpath` framework, WebKit, `/usr/lib/libsqlite3`, six forbidden Info.plist keys, a missing manifest, a tracking manifest and an unreviewed resource bundle | 35 reviewed system libraries, no embedded code, no entitlements, no forbidden key, manifest declares no tracking or collection | 34 libraries, otherwise the same |
| Capability scan, `check-app-capabilities.py`: network, web view, StoreKit, AdSupport/AdServices, tracking permission, CloudKit, GameKit, push, analytics SDK names and modules, `dlopen` paths | `verify.sh`, per Release iOS app | `test-app-capabilities-check.py`: one binary triggers all ten categories; `URLSession` alone is network only; Swift-only StoreKit 2 is in-app purchase; a statically linked `Mixpanel` module is an SDK; a clean app passes | No reference in its one Mach-O file | Same |
| Localization, `check-localization.py` | `verify.sh`, per title | `test-localization-check.py`: a complete English and German catalog with plurals, reordered placeholders, `shouldTranslate` false and a manual key passes, as does a source-only title; refuses 12 defects, from a missing translation to a declared language that does not ship | Pass, source language only (no declared languages, empty catalog; 9 code keys fall back to their English text) | Same, 2 code keys |
| Asset provenance, `check-asset-provenance.py` | `verify.sh`, per Release iOS app | `test-asset-provenance-check.py`: refuses an unrecorded packaged file, an unrecorded new resource, a notice without a license, an upstream asset without a license, a packaged file with no source, an unrecorded app icon and a missing `CONTENT.md` | 5 sources traced, 1 third-party file (SplitMix64 notice) with license and attribution | 8 sources traced, 1 third-party |
| Reproducible build, `check-reproducible-build.py` | `verify.sh` rebuilds each Release iOS app into a second clean directory of equal path length | `test-reproducible-build-check.py`: the same source in two directories passes; a different path length is refused for `LC_UUID` only; changed code, a changed resource and an extra file are refused | Not bit-identical: 130 bytes of the string table differ (debug-map object paths); `LC_UUID` equal; executables identical after `strip -S`; resources identical | Same, 145 bytes |
| Network observation, `network_observation.py` inside `run-mobile-tests.py` | `test-mobile.sh`, every title and geometry, restart proof included | `test-network-observation.py`: mocked outbound TCP, an unexplained CFNetwork entry, an app never observed and sampler or log failures fail; live host and simulator apps opening a connection fail; idle ones pass. `test-mobile-runner.py` proves a seeded violation fails the whole run | [Pass](#network-observation) | Pass |
| Accessibility audits, `BlockAccessibilityUITests` | `test-mobile.sh` for Block Match | `testAuditGateFailsOnASeededViolation`: a DEBUG-only unlabeled 20-point control must come out of the same audit, filters and excuses as a failure | [Pass](#accessibility) | Not applied (the reference title carries the checklist) |
| Minimum runtime, `minimum-runtime` job | Hosted only, iOS 18.0, both geometries | `test-mobile-runner.py`: every title on both geometries gets an owned iOS 18.0 device with retries; a missing 18.0 runtime fails before any device exists; the workflow check fails if the job loses `ipad9`, the 18.0 pin, every-title coverage or the evidence globs | [Not run](#still-needs-hosted-ci) | Not run |

`verify.sh` runs the first seven self-tests and gates. The `verify` job's new step, "Check runtime gates against seeded violations", runs `test-mobile-runner.py`, `test-record-baselines.py` and `test-network-observation.py --simulator`.

### Self-test and verification results

| Check | Result |
| --- | --- |
| `python3 scripts/generate-project.py --check` | Current |
| `bash scripts/verify.sh <new dir>`, 22:38–22:43 | Exit 0, "Verification passed". Core 34, platform 39, `BlockContent` 7 and `DevelopmentContent` 7 tests; 11 CLI rejection cases; six builds; seven self-tests; every release gate passed on both titles |
| Self-tests, standalone | `test-foundation-check` 6, `test-app-bundle-check` 10, `test-app-capabilities-check` 5, `test-localization-check` 14, `test-asset-provenance-check` 9, `test-reproducible-build-check` 6, `test-required-reason-check` 4, `test-mobile-runner` 9, `test-record-baselines` 6 (including a real probe compile) and `test-network-observation --simulator` 11 PASS lines, each exit 0. The last ran on an owned iOS 26.0 iPhone 12 simulator |

### Reproducibility

Unsigned `xcodebuild build` Release executables keep the linker's debug map, whose object paths include the derived-data directory. Two clean builds are therefore never bit-identical, and `LC_UUID` changes when the path length changes. The gate compares what is stable: equal `LC_UUID`, identical executables after `strip -S`, identical resources and file sets. Archive builds strip the debug map (`STRIP_INSTALLED_PRODUCT`); this was not exercised. A release candidate is built by archive or from a derived-data path of fixed length.

## Minimum-runtime coverage

The `minimum-runtime` job is now a `fail-fast: false` matrix over `iphone12` and `ipad9`, each running every title on iOS 18.0 with retries, the fault classification and the network evidence. One geometry for both titles took 24 of the job's 60 minutes before this change, so both geometries in one job would not fit. It runs on pushes to the shared branches and on `workflow_dispatch` with `minimum_runtime=true`. It has not run with this change: there is no iOS 18 runtime locally. Its orchestration is covered by `test-mobile-runner.py`.

## Network observation

`test-mobile.sh` sampled the app's host process for internet sockets (`lsof`) and read the app's log for Apple networking subsystems through every test invocation on each device. One entry kind is listed as system-owned with its reason: `com.apple.network:activity`, the `nw_activity` telemetry objects that come to the app over XPC with its launch request. No socket appears with them. Any other networking entry fails the run.

| Title | Geometry | Samples (with app) | Largest gap with the app running | Log entries (system-owned) | App-originated activity |
| --- | --- | --- | --- | --- | --- |
| Block Match | iPhone 12 | 635 (575) | 2.76 s | 63 (63) | None |
| Block Match | iPad (9th gen) | 767 (638) | 1.61 s | 70 (70) | None |
| Practice | iPhone 12 | 658 (550) | 1.02 s | 69 (69) | None |
| Practice | iPad (9th gen) | 615 (517) | 1.86 s | 69 (69) | None |

The reports' overall largest gaps for the practice title, 17.5 s and 23.6 s, fall during the simulator restart proof, when no app process exists. Limits: a raw BSD socket opened and closed between two samples is invisible to the socket channel; the log channel covers Network.framework and CFNetwork traffic however short. The evidence covers only the flows the tests exercise; the release checklist's manual offline check covers the rest.

## UI runs

`GAMECORE_SIM_OWNER=integrator bash scripts/test-mobile.sh <new dir>`, every title on both geometries, 22:44–23:06, exit 0.

| Title | Geometry | Result | Retries |
| --- | --- | --- | --- |
| Block Match | iPhone 12 | 6 app-hosted and 7 UI tests passed | None |
| Block Match | iPad (9th gen) | 13 passed | `testAuditsPassOnEveryPageAtAccessibilityTextSize`, passed on retry |
| Practice | iPhone 12 | 28 passed; restart proof passed | None |
| Practice | iPad (9th gen) | 28 passed; restart proof passed | None |

**The iPad retry.** The first run failed on `menu-large-text elementDetection -: Potentially inaccessible text`, at the first audit and at its repeat one second later, with an element the audit could not resolve (frame `inf`). Following [CONTRIBUTING](../../CONTRIBUTING.md#ui-test-failures), the simulator log was scanned first: no N06, N09 or N10 signature. The failure screenshot shows a system notification, "Ready for Apple Intelligence", drawn over the Block Match menu by SpringBoard on the freshly created simulator. Its text is not in the app's accessibility tree, which matches an unresolvable `elementDetection` report. The retry, with the banner gone, reported nothing. No app change was made. The checklist and CONTRIBUTING now say to check the audit screenshot for a system banner first. S-4 below, an unresolvable `elementDetection` report on the iPad settings sheet, may have the same cause; that is unconfirmed.

## Baselines

`GAMECORE_SIM_OWNER=integrator python3 scripts/record-baselines.py <new dir> --launches 5`, 23:10–23:20, exit 0. Retained as [epic-08-simulator-baselines.json](epic-08-simulator-baselines.json). Conditions: Xcode 27.1, iOS 26.0 simulator, the host above with load averages 14.2 / 56.6 / 72.2 at the start and 145.7 / 173.5 / 134.8 at the end. The runtime member's quiet-host condition (load under about 2) was not met. Compare later baselines only with a run on a comparable host, or replace these after a quiet-host run.

How each signal is measured:

- **Launch:** process start to the first display-link frame after the app becomes active, over 5 `simctl launch` runs after `simctl terminate`: process-cold, with a warm file cache. The first launch after install is reported separately.
- **Scene updates:** intervals between successive `-[SKScene update:]` calls, from a test-only probe (`scripts/baseline-probe/BaselineProbe.m`) injected into the Debug app, while the title's fixed gameplay UI test runs. The titles have no frame diagnostics of their own. These are callback intervals, not presented frames.
- **Memory:** `phys_footprint` of the simulated app's host process.
- **Package:** unsigned Release iphoneos build; deflate zip of `Payload/<App>.app`.

| Title | Geometry | Launch median (min–max) | First launch after install | Scene update p50 / p95 / p99 / max | Intervals | Footprint at launch / peak |
| --- | --- | --- | --- | --- | --- | --- |
| Block Match | iPhone 12 | 447.0 ms (431.0–468.2) | 543.5 ms | 16.67 / 17.43 / 32.75 / 300.0 ms | 598 | 22.39 / 64.02 MiB |
| Block Match | iPad (9th gen) | 445.4 ms (434.6–456.7) | 477.9 ms | 16.67 / 17.28 / 28.77 / 269.7 ms | 627 | 22.72 / 62.78 MiB |
| Practice | iPhone 12 | 446.3 ms (438.1–447.4) | 719.6 ms | 16.67 / 17.25 / 20.27 / 266.7 ms | 763 | 22.47 / 64.02 MiB |
| Practice | iPad (9th gen) | 441.3 ms (432.7–824.0) | 453.8 ms | 16.67 / 17.02 / 20.32 / 264.2 ms | 759 | 22.36 / 63.08 MiB |

| Title | App bundle | Executable | Zip |
| --- | --- | --- | --- |
| Block Match | 1,335,319 bytes, 12 files | 1,262,408 bytes | 358,702 bytes |
| Practice | 1,370,067 bytes, 15 files | 1,296,048 bytes | 370,349 bytes |

The practice title's update streams each include four pauses of 2.6–5.2 s. The recorder keeps gaps of 1 s or more out of the statistics and lists them in the JSON; their causes were not investigated. The single maxima of 264–300 ms were not investigated either.

## Accessibility

[Checklist](../../docs/accessibility-checklist.md) and the reference title's [record](../../Games/BlockTitle/ACCESSIBILITY.md). In this run, every automated item passed on both geometries: the audits of menu, settings, play, pause, success and failure at the default size and at AX3, the seeded-violation test, the block-button input path, reduced motion and distinct shapes and names. The accessibility member's earlier runs, on the same tests, also passed 13 of 13 on the first attempt on both geometries, in dark appearance, and at the system AX5 size on iPad. iPhone AX5 covered menu and settings, with the play page checked from the recording.

Fixed in the title: F-1, block button text contrast; F-2, one button a row at accessibility sizes instead of one letter per line; F-3, Block Match's DEBUG text-size and reduced-motion overrides.

Tracked shared-shell actions, each excused only on the settings page of the audit test and recorded with the exact `GamePlatform` change:

| ID | Finding | State |
| --- | --- | --- |
| S-1 | The DEBUG text-size override does not reach the settings sheet, so the large-text audit skips settings | Open; then remove the skip |
| S-2 | Section headers, secondary text, the accent-tinted Export and the red Reset/Delete fall below 4.5:1 | Open |
| S-3 | Settings rows reported as not scaling or clipped; the AX3 recording shows them scaling | Open; confirm after S-1 |
| S-4 | iPad settings: one unresolvable `elementDetection` report | Open; may be a system banner, as in the retry above |

Not run: Accessibility Inspector's heading rotor and the focus checks after page changes (item 2), Full Keyboard Access (item 7) and the Grayscale color filter (item 4). Each needs an interactive simulator session. As a stand-in for Grayscale only, the iPhone 12 play-page audit screenshot was converted to grayscale (`sips`, Generic Gray Gamma 2.2): circle and square blocks remain distinct on the board and on the buttons. That is not the color filter on both geometries. VoiceOver speech, Voice Control and haptics belong to the hardware check.

## Release checklist, hardware check and ADR-009

- [Release checklist](../../docs/release-checklist.md): candidate identity, the automated gates with what to record, the manual offline and network check, App Store privacy answers with how each is verified (required-reason APIs included), the privacy-description text for local reset and export, accessibility, provenance, a release-notes template and the hardware item.
- [Hardware check](../../docs/hardware-check.md): startup, frame pacing against ADR-002's p95 ≤ 20 ms and p99 ≤ 33.4 ms, memory against 150 MiB and 250 MiB, thermal behavior and touch, on an iPhone 12 or slower and an iPad (9th generation) or slower. The 2-second startup trigger and the thermal ceiling of Fair are new review thresholds, not ADR-002 budgets; they stand until a lead adjusts them.
- [ADR-009](../decisions/ADR-009-release-scope-without-hardware.md): a title may reach a reviewed release candidate on simulator evidence, but is not distributed until the hardware check passes. It lists what stays unmeasured: startup, frame pacing, memory, thermal and battery, GPU, touch, accessibility output, audio and haptics, minimum OS on a device, distribution and Files export.

## Integration review

The three member change sets did not overlap in files. Changes made during integration:

- **Provenance gate red on both titles** (bundle member findings 1–2): each `CONTENT.md` now links the app icon source, and Block Match's SplitMix64 sentence names its public-domain license and that it needs no attribution. The same sentence is in `scripts/title-template`, so a scaffolded title passes the gate.
- **`title.json` could not declare languages** (finding 4): `scripts/titles.py` accepts an optional `languages` list of unique BCP 47 codes. `check-localization.py` already requires it to include the catalog's source language. Checked by loading copies of the manifests with valid and invalid values.
- **S-4 missing from the title record:** the audit test excused S-4 without a matching entry in `ACCESSIBILITY.md`, which the checklist calls a defect; the entry is added.
- **Documentation:** CONTRIBUTING describes the new gates, the network observation, `GAMECORE_SIM_OWNER`, the baseline recorder, the release documents and the system-banner audit artifact. The privacy contract and the asset-provenance page name their gates.

Not changed: `verify.sh` does not run the three runtime self-tests, because they need simulators and the CI step covers them.

## Tracked actions

| Action | Owner |
| --- | --- |
| Run the three interactive accessibility steps on both geometries and record them in `ACCESSIBILITY.md` | Accessibility / Block Match |
| S-1 to S-4 shell changes, then remove the excuses and the large-text settings skip | `GamePlatform` |
| Populate both String Catalogs; give shared-shell strings a catalog and bundle (the `GamePlatform` package emits no `.stringsdata`) before any title declares a second language | Titles / `GamePlatform` |
| Re-record baselines on a quiet host, preferably with the CI toolchain, and replace the retained file | Release |
| Static-scan limits in the release record: Swift string literals of 15 bytes or fewer are inlined, so short `NSClassFromString` names escape; names built at run time and system frameworks acting for the app are outside the scan | Release checklist users |
| Both apps import `_dlsym` from the Swift toolchain's static compatibility libraries; no project object references it | Recorded, no action |
| Optional: an `ACCESSIBILITY.md` stub in `scripts/title-template` | Tooling |

## Still needs hosted CI

- The `verify` job on Xcode 26.6 / iOS 26.5 SDK: the six new self-tests, the release gates (a framework that 26.6 links outside `ALLOWED_SYSTEM_FRAMEWORKS` would be named by the bundle audit), one extra Release build per title, and the new runtime self-test step, within the 45-minute budget.
- The `foundation` matrix with network observation and `BlockAccessibilityUITests` on iOS 26.5.
- The `minimum-runtime` matrix on iOS 18.0 on both geometries (`gh workflow run mobile.yml -f minimum_runtime=true`, or a push), gated on the per-job status of `minimum-runtime (iphone12)` and `minimum-runtime (ipad9)`, with the NETWORK PASS line and `<model>-network.json` in each. The network observer and its log predicate have only been checked against iOS 18 with mocks.

## Acceptance

| Criterion | Verdict | Evidence |
| --- | --- | --- |
| CI runs the automated gates on every app target, and each gate fails on a seeded violation | Met locally; hosted run pending | `verify.sh` loops over every manifest title and runs in the `verify` job; network observation runs for every title and geometry in `foundation` and `minimum-runtime`; each gate's self-test fails without the refusal it seeds, and all ten passed locally |
| The reference title passes the automated gates, the minimum-runtime job and the accessibility checklist on both simulator geometries | **Not met** | Automated gates: pass. Minimum-runtime job: not run (hosted). Accessibility checklist: every automated and simulator-manual item passed except three interactive steps that did not run (Inspector headings and focus, Full Keyboard Access, Grayscale filter) |
| App-bundle audit finds no ad, analytics, attribution, IAP, account, cloud or push integration and no app-originated network traffic during exercised flows | Met locally | Bundle audit and capability scan pass on both titles' Release builds; no app-originated activity in about 2,700 samples and 271 log entries across both titles and geometries |
| A reviewer can trace every packaged third-party asset to its license and attribution requirement | Met locally | The provenance gate traces every packaged file of both titles; the only third-party file, the SplitMix64 notice, links to a sentence naming its public-domain license and that it needs no attribution |
| Accessibility findings have either a fix or an explicit, tracked title-specific action before that title ships | Met | F-1 to F-3 fixed with tests; S-1 to S-4 tracked with the exact shell change, each excused only on its page and recorded in the title record; the retry's banner artifact recorded above |

Epic 08 stays open until the three interactive accessibility steps pass on both geometries. After that, the epic is complete for mobile simulator acceptance, with the hosted `verify`, `foundation` and `minimum-runtime` results named as pending.
