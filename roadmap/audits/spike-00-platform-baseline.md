# Spike 00 — Platform baseline evidence

**Date:** 2026-09-30  
**Branch:** `codex/spike-00-platform-baseline`, started from `integration/first-party-foundation` at `0c98977`.  
**Status:** Experiment implemented; strengthened terrain collision/settling integration tests passed on both device-geometry simulators; final source builds and pure tests passed; macOS pointer/keyboard and terrain were observed in a partial run, but full macOS runtime validation remains open, and physical acceptance and minimum-runtime checks remain open. This report does not close Spike 00 or unblock Epic 01 implementation.

## Scope and platform choice

The [checked-in experiment](../../experiments/platform-baseline/README.md) hosts original SpriteKit blocks/panel scenes and a small RealityKit heightfield in SwiftUI. Code uses generated geometry/colors and Apple SDKs with no external package, resource or entitlement dependency. Its Foundation-only models have their own pure test package. Neither that package nor the Xcode app is the production `GameCore` skeleton.

The user selected **iPhone 12 and iPad (9th generation)** as physical acceptance devices and **macOS later** for release. [ADR-002](../decisions/ADR-002-platform-rendering-baseline.md) records proposed iOS/iPadOS 18 and development macOS 15 floors, first-party renderer responsibilities, initial budgets and fallback. GateEngine stays declined under preflight; no mandatory comparison is retained.

## Observed environment

- Xcode 27.0 (`27A266a`), Apple Swift 6.4 (`swiftlang-6.4.0.34.1`); app/package Swift 5 language mode.
- arm64 macOS 27.0 (`26A428`), Apple SDKs 27.0. Build/test outputs are under `/private/tmp/gamecore-spike00-*` rather than in source control.
- Installed simulator runtimes include iOS 17.4 and 26.0. The former is below the experiment floor; there is no installed iOS 18 runtime, so deployment-target compilation is not a minimum-runtime pass.
- Disposable iOS 26.0 simulators matching iPhone 12 and iPad (9th generation) screen geometry were created for interaction checks. They emulate geometry/input paths, not the devices' CPU, GPU or memory limits.
- Device inventory did not show either selected acceptance device connected. Paired/offline devices do not satisfy that gate.

Initial sandbox restrictions blocked CoreSimulator access and Swift compiler plugins/cache writes. Permitted executions outside the shell sandbox allowed these tools to run; that was an environment limitation rather than a source incompatibility. Some failed UI runs stalled in developer-tool teardown and were interrupted. One occurred while local firewall approvals were pending, but another stalled after firewall allowance; the available evidence does not establish a single cause for the hangs. The stalled task was terminated without globally restarting or shutting down unrelated simulators. No app-network or privacy conclusion is inferred from developer-tool firewall activity.

## Executed checks

Pure tests run with:

```sh
swift test --package-path experiments/platform-baseline \
  --scratch-path /private/tmp/gamecore-spike00-logic-build
```

**Eight XCTest tests passed with zero failures.** They cover resized board hit geometry and edge exclusion, terrain locality/depth clamping/topology/upward winding, normalized surface normals, bounded statistical windows, percentile calculations, nonfinite inputs and pause-gap exclusion. The additional Swift Testing runner reports zero tests because this package uses XCTest; it does not negate the XCTest result.

Project generation uses only Python's standard library:

```sh
python3 experiments/platform-baseline/scripts/generate-project.py
```

Unsigned Debug/Release builds and UI-test commands are reproduced in the experiment README and `scripts/verify.sh`. The simulator test scheme executes one integration test, with parallel testing disabled. It records screenshots and local diagnostic text in `.xcresult` attachments. The app generated Info.plist contains no camera, microphone, tracking, Game Center or cloud configuration. The limited source privacy scan passes; runtime traffic observation and a distribution privacy manifest are separate future checks.

## Final evidence

Retained excerpts preserve inspected log results independently of temporary full logs/result bundles. The [final mobile source snapshot](../../experiments/platform-baseline/evidence/final-mobile-source-sha256.txt) identifies current app and UI-test sources. The latest [build verification](../../experiments/platform-baseline/evidence/final-ax-verification.txt) compiled the app sources; final mobile runs compiled the current test helpers. Earlier source snapshots/excerpts are historical and are not the final proof below.

| Check | Observed result | Retained evidence / limit |
| --- | --- | --- |
| Final pure tests, privacy scan, unsigned Debug/Release macOS and iOS Simulator builds | Passed; eight XCTest tests, no failures; verification exit 0 | [Verification excerpt](../../experiments/platform-baseline/evidence/final-ax-verification.txt); static scan does not certify runtime traffic |
| Final iPhone 12 geometry, iOS 26 integration | One test passed, no failures, 45.351 seconds; bundle finalized | [Run excerpt](../../experiments/platform-baseline/evidence/iphone12-ios26-final.txt); [landscape screenshot](../../experiments/platform-baseline/evidence/iphone12-ios26-final-landscape.png) visually inspected |
| Final iPad (9th generation) geometry, iOS 26 integration | One test passed, no failures, 46.315 seconds; bundle finalized | [Run excerpt](../../experiments/platform-baseline/evidence/ipad9-ios26-final.txt); [landscape screenshot](../../experiments/platform-baseline/evidence/ipad9-ios26-final-landscape.png) visually inspected |
| macOS signed runtime iterations | Pointer/arrow/Space, paused input and terrain rest observed in a partial run; full suite did not pass | [Partial evidence](../../experiments/platform-baseline/evidence/macos-partial-runtime.txt); missing accessibility element in an earlier run, inconsistent initial click delivery on later retries |
| Physical acceptance / minimum runtime | Not run | Acceptance hardware unavailable; no iOS 18 runtime installed |

## Final simulator diagnostic samples

These scene-update callbacks were recorded under UI automation on the development Mac. They do not measure actual GPU presentation, dropped display frames or physical-device performance. Footprint is a current process snapshot, not peak memory. Short windows include automation/startup overhead.

| Geometry / phase | Intervals | p50 / p95 / p99 (ms) | Worst (ms) | >33.3 ms | Footprint snapshot (MiB) |
| --- | ---: | --- | ---: | ---: | ---: |
| iPhone / blocks | 355 | 16.7 / 16.7 / 29.0 | 54.3 | 3 | 39.9 |
| iPhone / panel | 300 | 16.7 / 16.7 / 16.7 | 30.3 | 0 | 43.2 |
| iPhone / terrain | 424 | 16.7 / 17.0 / 21.0 | 63.8 | 1 | 66.4 |
| iPhone / resumed blocks | 355 | 16.7 / 16.7 / 28.3 | 41.9 | 3 | 73.0 |
| iPad / blocks | 357 | 16.7 / 16.7 / 16.7 | 43.4 | 2 | 39.4 |
| iPad / panel | 300 | 16.7 / 16.7 / 16.7 | 16.7 | 0 | 42.0 |
| iPad / terrain | 424 | 16.7 / 16.9 / 18.1 | 70.8 | 1 | 66.9 |
| iPad / resumed blocks | 358 | 16.7 / 16.7 / 16.7 | 33.3 | 2 | 68.5 |

Both runs observed revision 2 contact and sustained rest at y=-0.007, x/z=-0.480/-0.480 (scene units). Mesh/collision generation was 1.30/15.12 ms then 1.11/19.34 ms on iPhone geometry, and 1.39/14.93 ms then 1.00/14.36 ms on iPad geometry. These are individual CPU/asynchronous-wait observations, not p95 summaries or GPU-completion timings. They do not approve the proposed physical budgets.

## Interaction and lifecycle findings

The simulator checks exercise touch activation for blocks and panel, no cell activation while paused, a terrain revision installed after a drill, a collision event, a targeted surface tap causing another revision, rotation, and home/background/reactivation in the final mobile runs. The corrected collider and sustained-rest check passed on both device-geometry simulators. Pure geometry tests independently cover different viewport sizes. Manual VoiceOver, iPad pointer/keyboard, physical collision feel and minimum-OS behavior remain unverified.

Two useful hosting findings changed the sample: a SpriteView initially created during an inactive lifecycle phase could retain native pause state after foregrounding, so the host now synchronizes both `SKScene.isPaused` and its native `SKView.isPaused`. Changing the scene argument could leave the previous scene displayed, so the host uses an explicit view identity for each mode and pauses inactive scenes. Integration tests now verify actual mode-specific actions rather than accepting that a mode button was tapped.

Viewport diagnostics have their own callback/HUD field so resizing cannot overwrite a cell action. `AnyLayout` keeps terrain ownership stable across compact layout changes. The final tests check landscape control bounds and retained screenshots were visually inspected on both simulator geometries. Hardware safe areas remain unverified. Terrain subscriptions are cancelled on disappearance, pause gates input/physics, and discarded/failed async collision rebuilds roll simulation back to the displayed mesh. These lessons do not establish production module contracts.

## Terrain evidence and limits

The workload is a 25 × 25 heightfield: 625 vertices, 1,152 triangles, radial excavation clamped at 0.45 scene units, fixed topology. Finite-difference normals plus a rough material and directional light make slopes readable. Mesh generation, static collision generation and simulation are separately owned; a dynamic sphere drops over the last excavated patch. Surface input uses the collision hit position converted into terrain-local coordinates. There is no drag excavation or volumetric cave/chunk implementation.

Timing callbacks distinguish CPU mesh work, asynchronous collision generation and scene-update cadence. A frame callback is not a GPU-presented frame; memory is current physical footprint, not peak. Samples taken under an automated simulator test include startup/accessibility overhead and cannot establish the physical performance budgets. No Metal extension or different engine is justified from those samples.

## Debugging lessons

The initial mesh-resource collider reported sphere contact at the original flat height rather than the drilled patch. Generating the static collision shape directly from heightfield vertices and faces resolved that simulator reproduction. An instantaneous low-speed check then falsely classified a bounce apex as settled; the final probe requires 0.75 seconds of stable height and low speed, with zero restitution. Both final simulator runs observed contact and sustained rest at y=-0.007 over the drilled patch. These are prototype observations, not physical-device or final-game guarantees.

Earlier collision-event-only checks, bounce-apex false rest and clipped landscape captures prompted stronger sustained-rest/control-containment checks and an explicit framed host. The final mobile runs supersede those iterations. Some developer-tool teardown runs stalled; final mobile evidence uses successfully finalized bundles, without attributing all earlier hangs to firewall behavior.

## Remaining acceptance gates

Before closing the spike, finish full macOS runtime validation, then execute the [physical procedure](../../experiments/platform-baseline/README.md#physical-acceptance-procedure) on both selected devices: Release build and minimum-OS checks, sustained actual display pacing, peak memory/pressure, resize/safe areas, pointer/keyboard/touch, terrain input/contact correctness, background/interruption behavior and offline/permission observations. Record the device and workload with each number. The current simulators and API availability checks do not substitute for those runs.

The provisional budgets and fallback are in ADR-002. If terrain cannot meet them, first bound collision/update work with measured evidence; Spike 11 owns the eventual dig-mechanic feasibility. A 2D excavation title remains the explicit fallback. Epic 01 implementation remains gated; its license/contribution/privacy documentation can be prepared independently.
