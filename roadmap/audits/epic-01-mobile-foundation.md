# Epic 01 — Mobile foundation evidence

**Date:** 2026-10-01

**Branch:** `codex/mobile-foundation`

**Status:** Complete. Local verification and hosted mobile CI passed; Epic 02’s entry gate is satisfied. Runner interruption/cleanup fixtures passed; review found no remaining material issue.

## Scope and source identity

The original mobile skeleton contains `Packages/GameCore`, `Packages/GamePlatform` with a local core dependency, `Games/DevelopmentTitle`, a UI smoke test, generated `GameCore.xcworkspace`/project and mobile build/test automation. Core/platform packages reserve boundaries without inventing domain APIs. The title imports both and displays “Foundation ready.” No gameplay, persistence or playable shell is implemented. The disposable renderer experiment is outside production targets.

[ADR-003](../decisions/ADR-003-simulator-mobile-foundation.md) accepts simulator development and defers macOS. Project-authored code, docs and resources use [MIT](../../LICENSE); no candidate code/assets or remote package dependencies are included.

At validation, HEAD was `a9c296a34d3bf57897d0c9ac4b1b69a65d888a2e` and the implementation was uncommitted. That historical HEAD is not the tested implementation revision. The [machine-readable evidence](epic-01-mobile-foundation-evidence.json) records `worktreeDirty: true` and actual source SHA-256 values. The same evidence record’s clean-copy input hashes identify the files used for the independent filesystem-copy build. Later runner-review changes are identified separately; these hashes preserve the earlier executed sources.

## Environment and commands

Local checks used Xcode 27.0 (`27A266a`), Swift 6.4 compiler, Swift 5 language mode, SDK 27.0 and iOS Simulator 26.0 (`23A5287g`). Production deployment floor is iOS/iPadOS 18.0; no minimum-runtime execution is claimed.

```sh
bash scripts/verify.sh /private/tmp/gamecore-mobile-foundation-20261001
bash scripts/test-mobile.sh /private/tmp/gamecore-mobile-foundation-ui-20261001
```

The hosted workflow passed on a clean committed checkout of `2d7bcf925963640fb53395f47a887009941a45ef` using `macos-26`, Xcode 26.6 (`17F113`) and iOS Simulator 26.5 (`23F77`). [Run 36933015783](https://github.com/1cf2ab6aafa31a3209ce70/1cf2ab6aafa31a3209ce70/actions/runs/36933015783) completed successfully on 2026-10-01. Downloaded artifact inventory records `worktreeDirty: false`; both finalized simulator result bundles report one passing test with zero failures or skips. Build, simulator tests and evidence upload all passed. These hosted results supplement the distinct local Xcode 27 observations.

## Results

| Check | Local result and scope |
| --- | --- |
| Generator/architecture/static privacy checks | Passed; validates generated consistency, local package graph, renderer-independent core, target/Info.plist inventory and selected forbidden imports/APIs |
| Core and platform packages | Core test target compiles; platform package builds. Zero runtime core test cases exist because the core has no domain behavior yet. |
| Application builds | Debug and Release generic iOS Simulator plus unsigned Release generic iOS SDK builds passed. SDK build is compilation, not hardware execution/signing acceptance. |
| iPhone 12 geometry | Final `.xcresult`: 1 UI test passed, 0 failed/skipped |
| iPad (9th generation) geometry | Final `.xcresult`: 1 UI test passed, 0 failed/skipped |
| UI coverage | Empty-title launch, readiness label, portrait/landscape orientation and label containment, home/background/reactivation. Portrait/landscape screenshots retained; both landscape captures visually reviewed without clipping. Result summaries contain no runtime warnings. |
| Runner process fixtures | Passed success/error, timeout, external Ctrl-C exit 130 and SIGINT/SIGHUP-resistant descendant cleanup with file output; command leader reaped. These are runner tests, not app runtime cases. |
| Script/workflow syntax | Bash syntax and Python compilation checks passed; workflow YAML parsed with Ruby/Psych. No hosted execution is inferred. |
| Clean filesystem-copy build | Passed with fresh build directories, no copied caches or `.git`; used Git-listed tracked and nonignored untracked files. This is not validation of a clean committed checkout or hosted checkout. |
| Release bundle review | Simulator and iOS bundles contain only executable, Info.plist and PkgInfo. MinimumOSVersion 18.0; no entitlement files, permission keys or background/ATS configuration. Linkage contains only Apple system frameworks and runtime libraries. No privacy manifest is currently bundled; final API/resource declarations need review before distribution. |

The test runner created and deleted only its own disposable simulators; both UUIDs were confirmed absent from the post-run inventory. Simulator screen geometry does not emulate physical CPU/GPU, thermal, battery or memory-pressure behavior. Static source and bundle inspection support the empty app's privacy boundary but do not certify all-path runtime traffic.

## Local artifacts

Full outputs remain in temporary local storage and may be removed by system cleanup. This report and retained source inventories preserve the result summary and tested-source identity independently.

| Artifact | Local path |
| --- | --- |
| Main build outputs/logs | `/private/tmp/gamecore-mobile-foundation-20261001` |
| Runtime inventory, build/test logs, finalized result bundles and screenshot exports | `/private/tmp/gamecore-mobile-foundation-ui-20261001` |
| Independent source copy | `/private/tmp/gamecore-foundation-clean-kk0l00m6` |
| Clean-copy build output | `/private/tmp/gamecore-foundation-clean-verification-kk0l00m6` |
| Clean-copy command log | `/private/tmp/gamecore-foundation-clean-verification-kk0l00m6.log` |
| Runner fixture summary | `/var/folders/b2/p6vsggfd46b7pbtjgdjxt1440000gn/T/gamecore-group-retry-review-kgeg144t/summary.txt` |
| Bundle inspection | `/private/tmp/gamecore-foundation-clean-verification-kk0l00m6/bundle-review.json` |

## Acceptance closure and release limits

The published foundation branch and passing hosted workflow close Epic 01 acceptance. Implementation, local checks and review are complete. No physical device or Mac application check is required. Minimum-OS execution, accessibility, representative workloads, runtime privacy and distribution signing remain mobile release checks as features arrive. The earlier experiment's eight pure tests are separate evidence, not production core test coverage.
