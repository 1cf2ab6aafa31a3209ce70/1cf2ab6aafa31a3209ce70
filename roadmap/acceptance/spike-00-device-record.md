# Spike 00 — Mobile simulator acceptance record

**Status:** Accepted for foundation development on 2026-10-01 under [ADR-003](../decisions/ADR-003-simulator-mobile-foundation.md). No physical-device acceptance result is claimed.

The user confirmed that no physical device is available and directed simulator-based mobile development. iPhone 12 and iPad (9th generation) now identify simulator screen geometries for layout/input coverage. macOS is deferred and is not a completion gate. This decision replaces the earlier requirement to wait for connected acceptance hardware.

## Retained development acceptance

| Field / check | Recorded evidence |
| --- | --- |
| Evidence date | 2026-09-30; accepted under revised scope on 2026-10-01 |
| Runtime / geometry | iOS 26.0 Simulator; iPhone 12 and iPad (9th generation) geometries |
| Toolchain / language | Xcode 27.0 (`27A266a`); Swift 6.4 compiler, Swift 5 language mode |
| Source identity | [Final mobile source hashes](../../experiments/platform-baseline/evidence/final-mobile-source-sha256.txt) |
| Build configurations | Debug and Release simulator builds passed; [verification excerpt](../../experiments/platform-baseline/evidence/final-ax-verification.txt) |
| Pure logic | Eight XCTest tests passed |
| iPhone interaction | One integration test passed, 45.351 seconds; [run excerpt](../../experiments/platform-baseline/evidence/iphone12-ios26-final.txt) |
| iPad interaction | One integration test passed, 46.315 seconds; [run excerpt](../../experiments/platform-baseline/evidence/ipad9-ios26-final.txt) |
| Covered paths | Blocks/panel touch, paused-input exclusion, terrain mesh/collider rebuild and sustained rest, surface tap, rotation/control containment, foreground restoration |
| Visual evidence | Final landscape captures inspected on both geometries; linked in the [audit](../audits/spike-00-platform-baseline.md#final-evidence) |
| Privacy evidence | Limited source scan passed; does not certify all-path runtime behavior |

Simulator geometry is not physical CPU/GPU or memory emulation. The audit's timing samples measure scene-update callbacks; footprint values are current process snapshots. No physical display pacing, thermal, battery or peak-memory target is marked passed.

## Future mobile validation

These checks belong to representative development workloads or distribution readiness, not a requirement to obtain physical hardware before implementing the foundation. Record pass, fail or not tested and the exact environment for each run.

| Check | Current boundary / next evidence |
| --- | --- |
| Minimum runtime | iOS/iPadOS 18.0 deployment target compiles; no 18.0 simulator runtime is installed. Exercise critical paths when a compatible runtime or other environment is available before distribution. |
| Representative performance | Profile sustained board/panel and terrain workloads in the simulator. Record host/runtime and distinguish update intervals, actual presentation measurements and memory metrics. Physical thermal/battery behavior remains unavailable. |
| Terrain workload | Run the fixed protocol below when evaluating rebuild costs. The retained integration suite does not claim the 50-command benchmark was executed. |
| Accessibility / alternate input | Exercise VoiceOver, larger text, reduced motion and available pointer/keyboard paths in the mobile test environment. |
| Offline / permissions | Exercise implemented paths offline; record prompts, observation method, coverage and any unexpected traffic. Review the actual built bundle and privacy declarations before distribution. |
| Signing / distribution | Validate mobile signing, release metadata and intended distribution requirements when preparing a release. |

Earlier proposed workload targets remain reference goals: 60 Hz interaction, presented-frame p95 ≤20 ms/p99 ≤33.4 ms, board/panel peak footprint ≤150 MiB, tiny-terrain peak footprint ≤250 MiB, mesh p95 ≤4 ms and collision regeneration p95 ≤12 ms. They are not simulator pass thresholds or accepted measurements. Compare like measurements and record limitations rather than lowering a target silently.

## Fixed terrain command and sample protocol

1. Enter Terrain, reset to a flat surface and wait for its installed revision and settled sphere. Record that baseline revision. Start the available profiling capture before the first drill; label scene-update intervals separately from any actual presentation measurement. Initial construction and reset timings are separate observations, excluded from the drill percentiles.
2. Press **Drill next crater** exactly 25 times. The current implementation walks five x positions from −0.48 to +0.48 in 0.24 increments for each of the same five z positions, with x changing fastest. Use the button sequence rather than freehand taps for this measured workload.
3. For each command, record its ordinal, installed revision, mesh milliseconds, collision milliseconds, contact/rest result and elapsed time since the preceding press. Issue the next command only after the current revision is installed and its sphere settles, and at least three active seconds after the preceding press. Record actual intervals; do not run builds, pause or background the app during this capture. If installation or settling does not complete within 15 active seconds, record a failure and stop the sequence rather than skipping it.
4. Reset, wait for the new flat baseline and settled sphere, and repeat the same 25 commands under the same capture conditions. Preserve the two run windows separately and state which timing and memory measurements the environment supports. Retain every mesh/collision pair, including slow samples.
5. Report each sequence's timings separately and the combined 50 drill samples. Compute p95 by nearest rank (`ceil(0.95 × sample count)` in sorted samples); state the actual sample count. An incomplete sequence is a failed workload, not a passing percentile result from its surviving samples. If presented-frame percentiles are available, use the instrument's documented method and state it independently of CPU timing statistics. Do not substitute scene-update intervals for presented frames.

Test freehand surface input, pause/interruption, edges and accessibility in separate correctness runs so those actions do not silently change the benchmark workload.

## Decision and handoff

Spike 00 is complete for the mobile foundation decision. Epic 01 can implement its original mobile package/title skeleton and satisfy its own build/test acceptance. Full dig-mechanic feasibility remains Spike 11's responsibility; the small heightfield does not decide caves, chunks or a final terrain title.

Preserve failures with trigger, expected/observed behavior and evidence. A later failure may narrow an adapter or title scope under ADR-003 without preventing unrelated core work. Physical observations can supplement this record if they ever become available, but no hardware acquisition or Mac validation is required for current development.
