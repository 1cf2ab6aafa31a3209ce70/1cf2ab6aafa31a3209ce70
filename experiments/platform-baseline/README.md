# Spike 00 platform baseline

An original, disposable SwiftUI application with an 8 × 8 SpriteKit block board, an unscrew-panel input/rendering placeholder, and a RealityKit surface-excavation experiment. It uses Apple SDKs and generated geometry/colors; there are no external packages or assets. This is an experiment, not the production shell or game core.

The acceptance devices selected for this spike are **iPhone 12 and iPad (9th generation)**. Mobile ships first; macOS is a development/portability target with release deferred. The proposed deployment floors are iOS/iPadOS 18 and macOS 15, matching the non-AR `RealityView` API used here. Physical-device and minimum-runtime validation remain required; simulator results cannot approve those gates.

## Build and run

The observed development toolchain is Xcode 27.0 (27A266a), Apple Swift 6.4, and SDKs 27.0. Both the experiment app and pure models use Swift 5 language mode. Python 3's standard library generates the checked-in Xcode project; XcodeGen and package downloads are unnecessary.

From this folder:

```sh
python3 scripts/generate-project.py
open PlatformBaseline.xcodeproj
bash scripts/verify.sh
```

Choose `PlatformBaseline` and an iOS 18+ device/simulator or My Mac. Device deployment needs your own signing team; no team or provisioning credentials are committed. The verification script builds unsigned Debug/Release macOS and iOS Simulator applications, runs pure-logic tests and a limited source privacy scan, and writes products under `/tmp`. Xcode services/compiler plugins must be allowed to run by the local execution environment. The script does not launch UI tests or certify runtime network behavior.

For repeatable simulator interaction checks, substitute an available simulator UUID from `bash scripts/inventory.sh`:

```sh
xcodebuild -project PlatformBaseline.xcodeproj -scheme PlatformBaseline \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UUID' \
  -derivedDataPath /tmp/gamecore-baseline-ui CODE_SIGNING_ALLOWED=NO build-for-testing
xcodebuild -project PlatformBaseline.xcodeproj -scheme PlatformBaseline \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UUID' \
  -derivedDataPath /tmp/gamecore-baseline-ui \
  -resultBundlePath /tmp/gamecore-baseline-ui-results.xcresult \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test-without-building
```

For local macOS UI tests, sign the runner ad hoc (no developer team is needed):

```sh
xcodebuild -project PlatformBaseline.xcodeproj -scheme PlatformBaseline \
  -destination 'platform=macOS' -derivedDataPath /tmp/gamecore-baseline-mac-ui \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build-for-testing
xcodebuild -project PlatformBaseline.xcodeproj -scheme PlatformBaseline \
  -destination 'platform=macOS' -derivedDataPath /tmp/gamecore-baseline-mac-ui \
  -resultBundlePath /tmp/gamecore-baseline-mac-ui-results.xcresult \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test-without-building
```

The unsigned macOS test runner was killed during bootstrap in this environment; the ad hoc signed runner executed. That launch failure does not establish an app-renderer failure. macOS keyboard testing explicitly focuses the renderer before sending keys. Runtime tests still require local Xcode/automation permissions.

Use a new result-bundle path for each run. UI tests exercise board and panel activation, blocked paused input, terrain regeneration/contact, rotation, and background/reactivation; retained attachments contain screenshots and local measurements. A partial macOS run observed pointer activation, arrow navigation, Space activation and terrain rest, but the full macOS suite did not pass; later retries had inconsistent window/input delivery. They do not replace hardware keyboard, VoiceOver, sustained performance, memory-pressure, or physical-device checks. Use the physical-device procedure below before accepting the spike.

## Controls and probe boundaries

- Blocks/panel: tap or click a cell to remove/restore it. On Mac, focus the renderer, use arrow keys to select, and Space/Return to activate. The panel is a representative plate/bolt visual and input workload, not an unscrew simulation.
- Terrain: tap/click the collision surface to excavate a radial patch, or use **Drill next crater** for a deterministic 5 × 5 drill sequence. **Reset terrain** restores a flat surface. A sphere drops after each rebuild to exercise static surface collision; contact height/revision and sustained-rest pose are reported locally. The sphere is constrained vertically over the excavated patch; this tests surface collision, not rolling behavior. Surface dragging is not implemented.
- Pause/Resume and app lifecycle suspend input and simulation. On resize, geometry and hit coordinates are recalculated; compact landscape layouts retain terrain state through `AnyLayout`.
- Simulation data stays separate from rendering: `BoardGeometry` and `TerrainHeightfield` are Foundation-only. SpriteKit receives board state; RealityKit receives heightfield positions/indices. The heightfield has 625 vertices and 1,152 triangles and cannot represent caves, overhangs, or disconnected voxel fragments.

The HUD is a disposable **in-memory diagnostic**, with no persistence or transport. It records the latest 3,600 scene-update intervals and nearest-rank p50/p95/p99, maximum interval, intervals over 33.3 ms, and the current process physical footprint. A lifecycle/mode change resets the window. SpriteKit timestamps come from `SKScene.update`; terrain timestamps come from `SceneEvents.Update`. Neither measures actual GPU presentation, input latency, or dropped display frames. Footprint is a snapshot, not a peak. Mesh/collision durations measure CPU work and asynchronous waiting, not GPU completion.

Do not compare samples taken during builds, simulator boot, screen recording, or debugger pauses as hardware performance results. Simulator memory and timing describe the host execution environment. No metric in this experiment is collected in a production title.

## Physical acceptance procedure

1. Record exact device model, OS, Xcode/toolchain, configuration, orientation, refresh rate, and build revision. Build Release and run on the selected iPhone 12 and iPad (9th generation), including the minimum OS where available.
2. Run blocks and panel for five minutes each. Perform repeated touches, rotate, pause/resume, background/reactivate, and confirm state/selection and hit coordinates remain valid. Exercise iPad pointer and a hardware keyboard separately. Use Instruments to capture actual display pacing, allocations/peak footprint, and input responsiveness; preserve an exported summary.
3. Run the 25-command terrain sequence, repeat it after reset, and record mesh/collision timings plus actual frame pacing and peak memory during updates. Verify that surface taps map to the touched patch, the sphere contacts the current mesh, and pause/rotation/backgrounding cannot update a removed or suspended scene. Inspect crater depth readability and collision near edges.
4. Proposed initial budgets: 60 Hz interaction; p95 presented frame interval ≤20 ms and p99 ≤33.4 ms over the sustained run; peak footprint ≤150 MiB for board/panel and ≤250 MiB for this tiny terrain workload. Target p95 mesh generation ≤4 ms and p95 collision regeneration ≤12 ms. These are provisional acceptance targets, not observed device results or guarantees for Epic 12's final terrain.
5. Record failures and scope changes in [the platform decision](../../roadmap/decisions/ADR-002-platform-rendering-baseline.md). If terrain misses the budget, first investigate collision resolution/update frequency; do not introduce Metal or an engine without a measured benefit. A 2D excavation title remains the fallback.

The [spike report](../../roadmap/audits/spike-00-platform-baseline.md) records executed commands/results and remaining gates. [Terrain notes](terrain-notes.md) explain the mesh/collision responsibilities and their limits.
