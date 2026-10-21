# Spike 11 — dig-feasibility evidence

**Date:** 2026-10-20. **Status:** Complete for mobile simulator acceptance. The prototype, simulator measurements, fixed budgets, decision record and risk list exist, module contract version 1 is confirmed for a terrain title, and the confirmation run set Epic 12's starting scope to 2D excavation ([ADR-008](../decisions/ADR-008-dig-terrain-feasibility.md#scope)).

The [experiment](../../experiments/dig-feasibility/README.md) and ADR-008 compare a heightfield, a voxel chunk mesh and a 2D approximation of one dig workload, plus a `LowLevelMesh` variant of the heightfield. All four run through one title-owned module on the production contract. Shared packages are unchanged.

## Summary

1. **First run.** No candidate met the decision rule. B fails correctness and the mesh row in every run; A, A2 and B each missed the iPhone 12 S p99 row once, and A also missed the mesh row once; C missed rows on the iPad geometry and both its iPhone 12 runs stayed void. The Spike 00 baseline, which the protocol puts first, ran last and broke the 25 ms p99 row on the iPhone 12 geometry at 29.3 ms, so the scope choice waited for a confirmation run.
2. **Confirmation run.** The unchanged baseline ran first and passed every interval row on both geometries. A2 then failed iPhone 12 run 1 at S p99 25.99 ms against 25.0, and iPhone 12 run 2 stayed void; both iPad runs passed every row. Under the unchanged rule, Epic 12 starts with 2D excavation (C) and first removes C's restart footprint growth ([confirmation run](#confirmation-run)).
3. **Object response and visuals.** The confirmation retains sphere probe records, with first contact separate from settled rest, for the counted A2 runs, and one after-trace screenshot per geometry. The verifier evaluates neither; this audit reads them.
4. **Observed limit.** On the iPhone 12 geometry, A2's idle window, with no digging, broke the 25 ms p99 row in 4 of 5 confirmation attempts while the Spike 00 terrain held 20.0 ms in the same session. Its cause is untested; reopening 3D needs a new decision record with new evidence.

All figures here are simulator scene-update intervals or host CPU, wall-time and footprint measurements, not device results. Hosted CI is not an exit item; it is listed under [Not measured](#not-measured).

## Source identity

| Item | Value |
| --- | --- |
| Base revision | `edfd9362262ba898a771030ff12566536574f9e9` on `integration/first-party-foundation`; branch `wip/spike-11-dig-feasibility`; no commits |
| Working tree during the runs | Dirty: `experiments/dig-feasibility/` untracked, `.github/workflows/mobile.yml` modified. During the confirmation run, Spike 11 documentation changes were also uncommitted; none is an experiment input |
| Experiment source SHA-256, first run | `52acfd0178d10e27d2134315493c7f103fb9950ca17f2c2b1cffa58bd78caf6e`, aggregated over the experiment's files. Per-file hashes cover 75 inputs, including `Packages/GameCore`, `Packages/GamePlatform` and `Games/DevelopmentContent` |
| Experiment source SHA-256, confirmation run | `b21815d808be2d9bf88ba86b67e9ada53ae972f56ba23d46f7b62a735dfe6436` over the same 75 inputs; only `scripts/verify.py` and `scripts/test-verifier.py` differ from the first run |
| Inputs before and after each run | Identical |
| Current tree | The confirmation run's 75 input hashes match the current files |

After the first run, the verifier changed to exclude a run that stays void after its repeats, and it gained `--summarize-only`. The retained `local-measurements.json` was recomputed offline with `verify.py --summarize-only` and carries the current verdicts. The `local-receipt.json` verdict block predates the change: it lists nine failed sprite rows, six of them from the void iPhone 12 runs, where the measurements list three. No Swift source changed. For this audit, `swift test` (28 passed), `generate-project.py --check`, `test-verifier.py` and `scripts/check-foundation.py` were rerun on the current tree and passed. The confirmation run used the current verifier, so `confirm-receipt.json` and `confirm-measurements.json` carry the same verdict.

## Toolchain, runtime and execution

- **Host:** Mac14,6 (Apple M2 Max), macOS 27.2 (`26B5112a`), Xcode 27.1 (`27A9275`), iOS Simulator 26.0 (`23A5287g`). Spike 00 ran on macOS 27.0 and Xcode 27.0 with an unrecorded chip.
- **Configuration:** Debug with DEBUG instrumentation and `SWIFT_OPTIMIZATION_LEVEL=-O` on every target, packages included. Release was built separately. Both builds exited 0.
- **Devices:** `verify.py` created one owned simulator at a time on iOS 26.0, `GameCore Spike11 owned iphone12` (iPhone 12) and then `GameCore Spike11 owned ipad9` (iPad (9th generation)). Every create, boot, shutdown and delete exited 0.
- **Order:** the pure tests and both builds ran once. Then, per geometry, the behaviour suite ran once and each candidate's two timing cases twice. Each timing invocation is two UI test cases, the sustained trace and five restart cycles, and took 193–201 s. The recorded commands took about 107 minutes in all.
- **Confirmation run:** same host, Xcode, simulator runtime and configuration. Step 1 ran 17:17–17:22 on owned simulators `GameCore Spike11 confirm-calibration <model>`, each deleted after its run. Step 2 ran 17:22–17:50 with `verify.py --candidate lowlevel --runs 2`: the pure tests and both builds once, then per geometry the A2 behaviour suite once and the timing cases until each run counted or reached three attempts. Each timing invocation took 198–205 s; the recorded commands took about 28 minutes.
- **Hosted CI:** the `dig_feasibility` job ([run 39525135428](https://github.com/1cf2ab6aafa31a3209ce70/1cf2ab6aafa31a3209ce70/actions/runs/39525135428), [hosted run](../../experiments/dig-feasibility/evidence/hosted-run.txt)) ran on a virtual M1 runner with Xcode 26.6 (`17F113`) and iOS 26.5 (`23F77`) at `b0276d8`, experiment hash `b21815d8…`. Debug and Release builds succeeded, including A2, and the behaviour suites passed 24 of 24 on both geometries. Every timing attempt broke the idle-window budgets (idle p99 27.6–153.9 ms), so every run was void, and the job reached its 180-minute timeout during the iPad heightfield runs. Hosted runners cannot rank candidates; the decision rests on the local runs.

## Workload and budgets fixed before the runs

The [research notes](../../experiments/dig-feasibility/research-notes.md) set these before any candidate run and name the Spike 00 observation behind each budget.

| Item | Value |
| --- | --- |
| Arena | 1.6 × 1.6 scene units (su), depth clamp 0.45 su, Spike 00 camera framing |
| Rule grid | 48 × 48 cells of 1.6/48 su |
| Brush | Radius 0.12 su; each dig deepens the centre by 0.02 su |
| Trace S | 600 digs at 10 per second: six serpentine rows at z = 4, 12, 20, 28, 36 and 44 cells, each from x = 4.0 to 43.6 in 0.4-cell steps. Rows 12 and 36 lie on chunk boundaries |
| Trace B | 300 digs at 30 per second: rows 20 and 28 again, then a column at x = 24 |
| Collectibles | 36 rule-owned items: 24 on trench centrelines, 4 on ridges under the burst column and 8 controls that no stroke touches. Expected score 24 after S and 28 after B, with no control collected |
| Physics (3D only) | Vertical sphere probes of radius 0.03 su, restitution 0, friction 0.8; presentation only |
| Windows | Warm-up 5 s (excluded), I idle 10 s, S 60 s, B 10 s, settle at most 15 s. Then R: five shell restarts, each followed by the first 100 S commands, a settle, 2 s idle and a snapshot |
| Delivery | One tap on "Run trace". An in-app driver issues command k at t0 + k/rate on `ContinuousClock` through the session's input gate |

| Row | Simulator budget | Window | Basis in Spike 00 simulator evidence |
| --- | --- | --- | --- |
| 1 | Interval p95 ≤ 20.0 ms | I, S | Terrain p95 17.0 and 16.9 ms, 424 intervals each |
| 2 | Interval p99 ≤ 25.0 ms | I, S | Terrain p99 21.0 and 18.1 ms |
| 3 | At most 0.5 % of intervals above 33.3 ms | I, S | Terrain 1 of 424 (0.24 %) |
| 4 | Worst interval reported; above 100 ms flagged | I, S | Terrain worst 63.8 and 70.8 ms |
| 5 | Mesh p95 ≤ 4.0 ms per command: extraction plus resource update over the dirty chunks, main-actor share reported | S | Four 625-vertex `MeshDescriptor` rebuilds, 1.00–1.39 ms |
| 6 | Collision p95 ≤ 25 ms per chunk, wall time including the async wait | S | Four 625-vertex `generateStaticMesh` samples, 14.36–19.34 ms |
| 7 | Collision lag p95 ≤ 100 ms and max ≤ 250 ms; for 2D, visual lag p95 ≤ 33.4 ms | S | One command interval at 10 per second |
| 8 | Score 24 after S and 28 after B with controls untouched; no accepted command lost; live outcome equal to the headless replay | S, B | Test plan's deterministic-rules scenario |
| 9 | Footprint growth from cycle 1 to cycle 5 ≤ 8 MiB, and no four consecutive deltas above 1 MiB; absolute values above 133 MiB flagged | R | Terrain snapshots 66.4 and 66.9 MiB |
| 10 | Entity and subscription counts equal to cycle 1 | R | Spike 00 subscription-cancellation lesson |
| 11 | Reload ≤ 500 ms in every cycle | R | No direct baseline; composed from 16 chunks at ≤ 25 ms collision plus 16 mesh builds at about 1.4 ms |

**Rules.** A run whose idle window I breaks row 1, 2 or 3 is void; it is repeated up to twice, and a run still void after that is excluded and reported. A candidate passes only if every budgeted row passes on both geometries in both runs. If no 3D candidate passes, Epic 12 starts with the 2D fallback. The unchanged Spike 00 baseline runs first; if it breaks the interval rows, the host is not comparable and any budget change is decided before candidate runs. These budgets rank candidates on this host only. They do not approve, replace or weaken ADR-002's physical targets.

**Deviations from the research workload.** The source deviations were in place for the whole run, since the input hashes match before and after it:

- The brush is `DigCore`'s sphere carve, whose bottom sits 0.02 su below the current surface, not the integer linear-falloff table. Heights are `Float`, not integer 0.001 su units.
- An item counts as collected when the rule field is open 0.099 su down rather than 0.10 su, so voxel cell boundaries round correctly (`Spike11Fixture.swift`).
- Only four items, the row-20 trench items, carry a sphere probe; the research made every item a sphere.
- C draws the heightfield rules top-down; the side-view mask is unused.
- One collision job per lane covers the whole dirty set and generates its chunks serially, instead of independent per-chunk jobs.
- Per-command logs go into each run's JSON report, which the verifier copies out of the app container, rather than into XCTest attachments.
- In the first run, the calibration ran after the candidate runs. The confirmation run restored the protocol order.

## First-run calibration: unchanged Spike 00 baseline

The [calibration record](../../experiments/dig-feasibility/evidence/spike00-calibration.txt) ran the unchanged `experiments/platform-baseline` at `edfd936`, `PlatformBaselineUITests/testBoardPanelTerrainAndLifecycle`, once per geometry, on the same host and runtime in Debug, after the candidate runs.

| Geometry | Terrain intervals | p50 / p95 / p99 (ms) | Worst (ms) | Above 33.3 ms | Mesh / collision samples (ms) |
| --- | ---: | --- | ---: | ---: | --- |
| iPhone 12 | 423 | 16.7 / 17.6 / 29.3 | 143.3 | 2 | 1.38 / 14.78, 1.16 / 19.27 |
| iPad (9th generation) | 424 | 16.7 / 16.8 / 21.6 | 153.9 | 1 | 1.12 / 15.23, 1.04 / 13.93 |

On the iPhone 12 geometry the baseline breaks row 2; its p95 and its share (2 of 423, 0.47 %) pass. On the iPad geometry it passes rows 1–3. Both terrain worst intervals exceed the 100 ms flag, and the blocks windows of the same runs contain 362.1 ms and 3,280.2 ms intervals. Mesh samples of 1.04–1.38 ms and collision samples of 13.93–19.27 ms sit close to Spike 00's 1.00–1.39 and 14.36–19.34 ms.

Idle windows often broke the interval rows. On the iPhone 12 geometry, 10 of 16 timing attempts were void: 2 for A, 2 for B and all 6 for C. On the iPad geometry, 3 of 11 were void: 1 for A and 2 for C. A2 had no void attempt; its iPhone 12 idle p99 was 24.72 and 24.58 ms. The [idle-window record](../../experiments/dig-feasibility/evidence/local-idle-windows.txt) keeps the idle window of every attempt, void ones included.

## Measurements

**Instrumentation.** Scene-update intervals come from `SceneEvents.Update` callback deltas on `ProcessInfo.systemUptime` for RealityKit and from `SKScene.update` `currentTime` for SpriteKit, with nearest-rank percentiles. Mesh and collision times come from `ContinuousClock`; collision is wall time per `generateStaticMesh` chunk, including the async wait. Memory comes from `task_info` `phys_footprint` snapshots and `ledger_phys_footprint_peak`. Host, runtime and build are as above. These are simulator diagnostics: they are not presented frames and not device results.

Each cell gives run 1 / run 2. `*` marks a budget miss in a counted run, and `v` marks a run still void after three attempts, whose misses are not marked. Source: [measurements](../../experiments/dig-feasibility/evidence/local-measurements.json).

### Scene-update intervals (ms)

| Candidate | Geometry | Attempts | I p95 | I p99 | S p95 | S p99 | S share > 33.3 ms (%) | S worst |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| A heightfield | iPhone 12 | 1, 3 | 17.0 / 17.1 | 24.3 / 24.9 | 18.2 / 18.0 | 27.2* / 24.0 | 0.17 / 0.03 | 37.7 / 43.5 |
| A heightfield | iPad (9th gen.) | 2, 1 | 16.9 / 17.0 | 22.4 / 24.4 | 18.0 / 17.9 | 22.6 / 22.9 | 0.00 / 0.08 | 33.2 / 33.5 |
| A2 lowlevel | iPhone 12 | 1, 1 | 17.1 / 17.1 | 24.7 / 24.6 | 17.7 / 17.5 | 26.7* / 24.7 | 0.08 / 0.14 | 35.4 / 33.8 |
| A2 lowlevel | iPad (9th gen.) | 1, 1 | 16.9 / 16.9 | 21.6 / 24.5 | 17.3 / 17.5 | 22.7 / 24.5 | 0.08 / 0.03 | 34.4 / 33.4 |
| B voxel | iPhone 12 | 2, 2 | 16.9 / 16.9 | 23.0 / 22.5 | 17.4 / 17.6 | 23.1 / 25.3* | 0.00 / 0.06 | 32.9 / 33.6 |
| B voxel | iPad (9th gen.) | 1, 1 | 17.0 / 17.0 | 24.5 / 23.8 | 17.3 / 17.4 | 22.7 / 23.6 | 0.03 / 0.14 | 33.6 / 34.1 |
| C sprite | iPhone 12 | 3v, 3v | 16.7 / 16.7 | 27.9 / 16.7 | 16.7 / 16.7 | 26.5 / 33.3 | 0.82 / 1.10 | 63.4 / 44.7 |
| C sprite | iPad (9th gen.) | 3, 1 | 16.7 / 16.7 | 16.7 / 16.7 | 16.7 / 16.7 | 16.7 / 16.7 | 0.50* / 0.64* | 42.7 / 43.7 |

No counted run flagged an interval above 100 ms; the largest in a counted I or S window was 43.7 ms. SpriteKit intervals are quantized at 16.7 ms, so occasional 33.3 ms skips decide C's share row.

### Mesh and collision (ms, window S)

| Candidate | Geometry | Mesh p95 | Main-actor p95 | Extraction p95 | Collision per chunk p95 | Collision per chunk max | Collision lag p95 | Collision lag max | Visual lag p95 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| A heightfield | iPhone 12 | 4.27* / 3.92 | 4.22 / 3.86 | 0.06 / 0.05 | 18.9 / 18.2 | 35.3 / 31.7 | 69.2 / 79.5 | 88.3 / 85.4 | n/a |
| A heightfield | iPad (9th gen.) | 3.90 / 3.63 | 3.87 / 3.58 | 0.05 / 0.05 | 18.2 / 17.6 | 34.6 / 29.6 | 77.4 / 78.8 | 79.8 / 82.6 | n/a |
| A2 lowlevel | iPhone 12 | 0.65 / 0.61 | 0.61 / 0.56 | 0.06 / 0.06 | 18.3 / 18.8 | 39.6 / 34.0 | 79.4 / 77.8 | 88.1 / 80.4 | n/a |
| A2 lowlevel | iPad (9th gen.) | 0.58 / 0.57 | 0.45 / 0.50 | 0.07 / 0.06 | 18.1 / 18.2 | 35.3 / 35.1 | 78.1 / 80.1 | 80.7 / 90.5 | n/a |
| B voxel | iPhone 12 | 5.64* / 5.84* | 4.41 / 4.58 | 1.31 / 1.31 | 17.5 / 17.9 | 31.3 / 37.3 | 57.6 / 60.9 | 79.2 / 78.9 | n/a |
| B voxel | iPad (9th gen.) | 5.55* / 5.88* | 4.42 / 4.62 | 1.27 / 1.36 | 17.5 / 17.5 | 33.9 / 25.9 | 60.5 / 58.6 | 77.1 / 78.4 | n/a |
| C sprite | iPhone 12 (v) | 0.47 / 0.44 | 0.45 / 0.41 | 0.03 / 0.03 | n/a | n/a | n/a | n/a | 14.8 / 13.7 |
| C sprite | iPad (9th gen.) | 0.39 / 0.40 | 0.37 / 0.38 | 0.03 / 0.03 | n/a | n/a | n/a | n/a | 11.9 / 13.4 |

Each counted 3D run covered 600 mesh jobs of at most four chunks. S produced 1,446 collision chunk jobs per heightfield run and 1,072 per voxel run. The 169-vertex heightfield chunks cost about as much per shape (p95 17.6–18.9 ms) as Spike 00's 625-vertex surface did per sample, so chunking did not lower the per-shape collision cost on this host.

### Restart cycles and correctness

| Candidate | Geometry | Footprint growth, cycle 1→5 (MiB) | Most consecutive deltas > 1 MiB | Snapshot range (MiB) | Ledger peak max (MiB) | Reload range (ms) | Entities / subscriptions | Score after S / B |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| A heightfield | iPhone 12 | 5.2 / 4.3 | 1 / 1 | 66.8–75.0 | 75.4 | 161–194 | 60 / 2 | 24/28, 24/28 |
| A heightfield | iPad (9th gen.) | 3.3 / 4.2 | 2 / 2 | 68.6–74.3 | 74.6 | 161–178 | 60 / 2 | 24/28, 24/28 |
| A2 lowlevel | iPhone 12 | 4.7 / 4.8 | 2 / 2 | 66.7–73.2 | 73.4 | 153–190 | 60 / 2 | 24/28, 24/28 |
| A2 lowlevel | iPad (9th gen.) | 2.8 / 3.3 | 2 / 2 | 68.2–71.5 | 72.0 | 161–182 | 60 / 2 | 24/28, 24/28 |
| B voxel | iPhone 12 | 7.8 / 3.3 | 2 / 1 | 76.9–84.7 | 84.9 | 97–156 | 53 / 2 | 26/30*, 26/30* |
| B voxel | iPad (9th gen.) | 5.8 / 5.1 | 2 / 2 | 77.8–83.7 | 83.8 | 108–139 | 53 / 2 | 26/30*, 26/30* |
| C sprite | iPhone 12 (v) | 12.1 / 12.3 | 4 / 4 | 51.2–63.6 | 63.8 | 3–4 | 39 / 1 | 24/28, 24/28 |
| C sprite | iPad (9th gen.) | 12.3* / 12.3* | 4* / 4* | 50.6–63.0 | 63.1 | 2–4 | 39 / 1 | 24/28, 24/28 |

B collected controls 32 and 35 in every run; no other candidate collected a control. Every run on every candidate restored the initial rule state in all five cycles, refused no command and matched its headless replay. No snapshot reached the 133 MiB flag. The ledger peak is the simulator process's lifetime peak, not device peak memory.

### Verdicts

| Candidate | Result | Failed rows |
| --- | --- | --- |
| A heightfield | Fail | iPhone 12: S p99, mesh p95 (run 1) |
| A2 lowlevel | Fail | iPhone 12: S p99 (run 1) |
| B voxel | Fail | Both geometries: score, mesh p95; iPhone 12: S p99 (run 2) |
| C sprite | Fail | iPad: S share, footprint growth, consecutive deltas; iPhone 12: both runs void |

No candidate passes the decision rule. ADR-008 explains why these runs could not decide between A2 and C, and defines the confirmation run below.

## Confirmation run

ADR-008 fixed four steps with every budget unchanged: run the unchanged Spike 00 baseline first; if it passes every interval row on both geometries, run A2 twice per geometry; if A2 then passes every row on both geometries in both runs, Epic 12 builds simplified 3D chunks on A2, otherwise it starts with C. Host, toolchain and runtime are as in the first run, and A2 ran at source hash `b21815d8…` ([source identity](#source-identity)). All interval figures are simulator scene-update callback intervals, not presented frames.

### Step 1: baseline first

The [confirmation calibration](../../experiments/dig-feasibility/evidence/confirm-calibration.txt) ran the same unchanged test as the first-run calibration, once per geometry, from 17:17 to 17:22, before any A2 run. The gate read the terrain window, the Spike 00 window the interval rows rest on ([budget basis](#workload-and-budgets-fixed-before-the-runs)). The blocks and panel windows include mode entry and taps, so they are not comparable; they are reported, not gated.

| Geometry | Window | Intervals | p50 / p95 / p99 (ms) | Worst (ms) | Above 33.3 ms | Gate |
| --- | --- | ---: | --- | ---: | ---: | --- |
| iPhone 12 | Terrain | 424 | 16.7 / 16.9 / 20.0 | 156.4 | 1 (0.24 %) | Passes rows 1–3 |
| iPhone 12 | Blocks | 451 | 16.7 / 16.7 / 57.6 | 326.5 | 11 | Reported |
| iPhone 12 | Panel | 301 | 16.7 / 16.7 / 27.5 | 125.3 | 3 | Reported |
| iPad (9th generation) | Terrain | 422 | 16.7 / 16.7 / 21.9 | 170.5 | 1 (0.24 %) | Passes rows 1–3 |
| iPad (9th generation) | Blocks | 356 | 16.7 / 16.7 / 24.6 | 308.7 | 3 | Reported |
| iPad (9th generation) | Panel | 300 | 16.7 / 16.7 / 16.7 | 34.1 | 1 | Reported |

Both terrain worst intervals exceed the 100 ms flag, as in the first-run calibration. Mesh and collision samples were 1.19 / 14.86 and 1.21 / 17.82 ms on the iPhone 12 geometry and 1.26 / 14.76 and 1.07 / 12.20 ms on the iPad geometry. The baseline passed, so step 2 ran.

### Step 2: A2 twice per geometry

`verify.py --candidate lowlevel --runs 2` ran from 17:22 to 17:50. The [window record](../../experiments/dig-feasibility/evidence/confirm-windows.txt) lists the idle window I and sustained window S of every attempt. An attempt is void when I breaks row 1, 2 or 3; void attempts' S values do not count.

| Geometry | Run | Attempt | Result | I p95 | I p99 | I share > 33.3 ms (%) | I worst | S p95 | S p99 | S share > 33.3 ms (%) | S worst |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| iPhone 12 | 1 | 1 | Void (I p99) | 17.00 | 26.50 | 0.168 | 33.79 | 17.15 | 23.78 | 0.083 | 41.60 |
| iPhone 12 | 1 | 2 | Counted; S p99 fails | 16.88 | 22.69 | 0.167 | 34.92 | 17.23 | 25.99* | 0.112 | 35.29 |
| iPhone 12 | 2 | 1 | Void (I p99) | 16.92 | 27.53 | 0.000 | 33.29 | 17.22 | 25.05 | 0.195 | 33.85 |
| iPhone 12 | 2 | 2 | Void (I p99) | 17.00 | 25.53 | 0.173 | 429.69 | 17.19 | 22.13 | 0.139 | 33.64 |
| iPhone 12 | 2 | 3 | Void (I p99, I share); run void | 16.90 | 33.05 | 0.505 | 39.43 | 18.99 | 33.15 | 0.885 | 217.33 |
| iPad (9th gen.) | 1 | 1 | Counted; passes | 16.88 | 23.57 | 0.000 | 26.15 | 17.13 | 22.55 | 0.000 | 33.11 |
| iPad (9th gen.) | 2 | 1 | Counted; passes | 16.85 | 21.23 | 0.000 | 25.91 | 17.21 | 23.88 | 0.084 | 49.52 |

Times are in ms. `*` marks a budget miss in a counted run. Idle windows held 577–600 intervals and S windows 3,502–3,598.

The counted runs' other rows all passed ([measurements](../../experiments/dig-feasibility/evidence/confirm-measurements.json)):

| Geometry | Run | Mesh p95 (main actor) | Collision per chunk p95 / max | Collision lag p95 / max | Footprint growth, cycle 1→5 (MiB) | Consecutive deltas > 1 MiB | Ledger peak (MiB) | Reload range (ms) | Score after S / B |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| iPhone 12 | 1 | 0.51 (0.46) | 17.5 / 34.2 | 76.9 / 92.9 | 2.7 | 1 | 72.1 | 176–177 | 24/28 |
| iPad (9th gen.) | 1 | 0.37 (0.33) | 17.1 / 28.4 | 76.0 / 80.9 | 3.0 | 1 | 74.0 | 170–181 | 24/28 |
| iPad (9th gen.) | 2 | 0.49 (0.41) | 17.2 / 31.9 | 77.0 / 92.7 | 3.2 | 0 | 74.5 | 166–182 | 24/28 |

Times are in ms: mesh is `ContinuousClock` CPU time per command and collision is wall time per chunk. Each counted run covered 600 mesh jobs and 1,446 collision chunk jobs, collected no control, refused no command, matched its headless replay, kept 60 entities and 2 subscriptions in every cycle and restored the initial rule state in all five cycles. The 28 pure tests, the 7 app-hosted and behaviour tests that apply to A2 on each geometry and every timing invocation passed, with no XCTest retry, and the inputs hashed the same before and after the run.

**Verdict.** Fail: 3 of 4 runs counted, iPhone 12 run 2 is void, and the one failed row is iPhone 12 S p99 ([receipt](../../experiments/dig-feasibility/evidence/confirm-receipt.json) and measurements agree).

### Object response and visuals

The [probe records](../../experiments/dig-feasibility/evidence/confirm-probes.json) cover the three counted runs. In each, the four row-20 probes (items 8–11) made first contact at y 0.033 su, 0.174–0.181 s after activation, on the initial collider. They first settled at 0.03 su, the rule rest height on the untouched surface, and finally at −0.42 su, the rule rest height over the 0.45 su depth clamp, 42.1–47.3 s after activation for items 9–11 and 79.5–79.6 s for item 8. Item 8 also settled once at −0.33 su, 0.022 su above its rule rest height of −0.352 su at that collider revision, before following the trench down. The after-trace screenshots for the [iPhone 12](../../experiments/dig-feasibility/evidence/confirm-iphone12-lowlevel-after-trace.png) and [iPad](../../experiments/dig-feasibility/evidence/confirm-ipad9-lowlevel-after-trace.png) geometries show the excavated trenches. The verifier evaluates neither record; physics is presentation and the score never reads it.

### Step 3: scope

A2 did not pass every row on both geometries in both runs, so step 3 applies as written: Epic 12 starts with C, SpriteKit `SKTileMapNode` drawing top-down depth bands over the heightfield rules, and first removes C's restart footprint growth. No budget changed. C was not run in the confirmation; its first-run misses (iPad S share 0.50 and 0.64 %, footprint growth of 12.31 and 12.25 MiB on the iPad geometry, both iPhone 12 runs void) are Epic 12 entry risks. On the iPad geometry the first-run calibration passed, at terrain p99 21.6 ms, so C's iPad misses do not rest on a failed calibration.

### Idle windows without digging

On the iPhone 12 geometry, A2's idle window I broke the 25 ms p99 row in 4 of 5 confirmation attempts, with I p99 22.69–33.05 ms; nothing digs during I. In the first run, the 3D candidates' idle windows on that geometry broke it in 4 of 10 attempts (A twice, B twice), while A2's two passed at 24.72 and 24.58 ms ([idle-window record](../../experiments/dig-feasibility/evidence/local-idle-windows.txt)). In the confirmation session the Spike 00 `RealityView` terrain window measured p99 20.0 ms on the same geometry. On the iPad geometry, no confirmation idle window broke a row, and 1 of 7 first-run 3D idle windows did (A, 32.04 ms).

So the iPhone 12 p99 miss is present without dig work. The dig prototype hosts RealityKit in a module-retained `ARView`; its idle cost on that geometry is a likely contributor, but the two scenes also differ and the cause is untested. This is a limit and a risk, not a reason to discount the miss. Reopening 3D for Epic 12 needs a new decision record with new evidence, such as physical-hardware measurements or an idle comparison of `RealityView` and `ARView` hosts, never a budget change applied to these runs.

## Cadence and determinism

- **Pure tests on the host:** 28 passed in the run and again at the current tree. The default workload is driven at 8.3, 16.7 and 33.3 ms frames and with a seeded 4–50 ms jittered sequence that includes one 0.4 s hitch; all match a `step()` replay in digest every 10 ticks, final digest and collection ticks, for all three fields. The Spike 11 fixture scores 24 and 28 on the heightfield with no control collected, and batching 1, 2 or 6 commands per tick gives one outcome digest for the heightfield and voxel fields. The voxel undercut (26 and 30, controls 32 and 35, surfaces untouched) is asserted as a measured deviation. Pending-geometry tests cover coalescing, refusal of stale completions after restart, collision cadence, re-queueing after a failed build, rule-field hit testing while the collider is stale, and a delayed-build loop that converges to a full rebuild.
- **In the app, both geometries:** the full 900-command trace with mesh installs delayed by 50 ms and collision installs by 200 ms passed for A, A2 and B; C ran with the 50 ms mesh delay and also at `preferredFramesPerSecond` 30 and 60. Each case asserts that the collected sets after S and B and the final outcome digest equal the headless replay, that no command was refused and, except for B, that the fixture's 24 and 28 hold.
- **Timing runs:** every counted run, in the first run and the confirmation, refused no command and matched its replay.
- **Not covered:** digest identity across compilers, CPU architectures or the CI toolchain, and tick-stamp identity in the app, which the outcome digest excludes by design.

## Restart, pause and reload

| Check | Candidates | Result |
| --- | --- | --- |
| Five shell restarts per timing run | All four | Initial rule state restored in every cycle; entity and subscription counts constant; reload times and footprint in the table above |
| Pause during a trace | A, B, C | Status unchanged over 2 s paused; no tick advance; sphere drift below the test's 0.001 su bound; resume completes with the replay outcome and nothing refused |
| Scene reload | All four | Outcome digest and revision unchanged; reload completes; entity and subscription counts unchanged |

A2 shares A's engine class and differs only in mesh installation; its pause case was not run separately. A job that finishes while paused is discarded and re-queued in code; the pause case checks the outcome, not the discard itself. C's footprint grows about 3 MiB per restart while node counts stay constant. The likely cause is that the prototype recreates its `SKScene` and `SKTileMapNode` on every reload; reusing the scene and resetting tiles is the untried mitigation, and Epic 12 applies it first.

## Touch and accessibility

- **Touch:** a UIKit pan or tap on the renderer view becomes a camera ray, resolved by ray-marching the current rule field and submitted through `DigSession.submit`. That is the only input gate, and it refuses input unless the shell reports the session as playing. Drag digs are spaced at least 0.4 cell apart, and surface touches are ignored while a scripted trace runs.
- **Non-precision path:** Move cursor north, south, east and west (`dig.cursor.*`) and Dig at cursor (`dig.dig`), as shell action buttons. The cursor steps by one brush radius. The cursor text, the score text and the `dig.surface` element carry a label, the value "Score n of 36" and a hint.
- **UI proof on both geometries, for A, B and C:** two cursor moves plus repeated Dig presses uncover the ridge item (score 1), with an accepted count equal to the presses plus two and the expected button labels. A native drag raises revision and accepted count; the same drag while paused leaves status unchanged. A2 uses A's input code and was not run separately.
- **Reduce Motion:** it disables C's collection animation in code, but no test exercises it. The 3D candidates have no decorative animation.
- **Shell layout:** `SharedShellView` scrolls vertically, so a drag that starts on the dig surface digs instead of scrolling; the UI tests scroll below the surface.
- **Not done:** VoiceOver and Dynamic Type passes, rotation and background/foreground interruption.

## Contract inspection

- `git diff --stat -- Packages` is empty against `edfd936`, and `scripts/check-foundation.py` passes.
- `DigModule` conforms to `GameModule` with `DigSession: ModuleSession` and registers through `ModuleHost` and `ModuleShellView` at contract version 1. It uses the `development-practice` catalog title and its `dig-sample-01` level, as the module-seam studies do.
- `DigCore` imports only `GameCore`, for `DeterministicRNG` and `TimedInput`. RealityKit and SpriteKit appear only in the experiment's `Sources/Engine`, and no file under `Packages` imports RealityKit, SpriteKit or Metal.
- Five app-hosted `DigSessionTests` passed on both geometries: contract version 1 and title identity, input gated by `playing` for all four candidates, restart restoring the initial rule digest, refusal of another title's request, and Debug option parsing.
- ADR-008 maps the title's needs onto version 1 members. No member is missing, and none carries a terrain type.

## Apple guidance rechecked on 2026-10-20

The [research notes](../../experiments/dig-feasibility/research-notes.md) give the SDK line references and source pages.

Against Xcode 27.1 and the iPhoneSimulator 27.1 SDK:

- `MeshResource.generate(from:)` is iOS 15, synchronous and `@MainActor`; `generateAsync` and `replaceAsync` are deprecated in iOS 18. The nonisolated async `MeshResource(from:)` and `replace(with:)` are iOS 18.
- `LowLevelMesh` and `MeshResource(from: LowLevelMesh)` are iOS 18 and `@MainActor`. Its `instanceCapacity`, `allowsPrimitiveRestart` and layout step members are iOS 27 only.
- `ShapeResource.generateStaticMesh(positions:faceIndices:)` is iOS 18, nonisolated and takes `UInt16` indices, so a shape holds fewer than 65,536 vertices. Apple warns that pre-processing large position counts takes significant time. The shape is static-only.
- The SDK declares no heightfield collision shape. `MeshInstancesComponent` is iOS 26, and `MeshDeformerComponent` and `NavigationMeshComponent` are iOS 27; none is used.
- Simulator sends Metal work to the host GPU, reports roughly Apple GPU family 2 features and offers no performance or memory measurement. Apple advises against using Simulator to design a rendering engine.
- `SKMutableTexture` updates carry a documented performance penalty; `SKTileMapNode` is iOS 10.
- A probe file using the iOS 18 APIs above typechecked with `-swift-version 5` for `arm64-apple-ios18.0-simulator`, and a probe using iOS 26 and 27 components failed as expected. That is a build boundary, not iOS 18 runtime coverage.

Sources: Apple's [LowLevelMesh](https://developer.apple.com/documentation/realitykit/lowlevelmesh), [MeshDescriptor](https://developer.apple.com/documentation/realitykit/meshdescriptor), [MeshResource](https://developer.apple.com/documentation/realitykit/meshresource), [Creating a plane with low-level mesh](https://developer.apple.com/documentation/realitykit/creating-a-plane-with-low-level-mesh), [Generating interactive geometry](https://developer.apple.com/documentation/realitykit/generating-interactive-geometry-with-realitykit), [`generateStaticMesh(positions:faceIndices:)`](https://developer.apple.com/documentation/realitykit/shaperesource/generatestaticmesh(positions:faceindices:)), [`generateStaticMesh(from:)`](https://developer.apple.com/documentation/realitykit/shaperesource/generatestaticmesh(from:)), [RealityKit updates](https://developer.apple.com/documentation/updates/realitykit), [Metal in Simulator](https://developer.apple.com/documentation/metal/developing-metal-apps-that-run-in-simulator) and [SKMutableTexture](https://developer.apple.com/documentation/spritekit/skmutabletexture).

## External candidates

Both repositories were cloned read-only outside the repository. Neither was built, and no code was copied.

| Candidate | Pinned source | License | Platforms and language | Maintenance | Decision |
| --- | --- | --- | --- | --- | --- |
| [heckj/Voxels](https://github.com/heckj/Voxels) | `bf3fe6767497c55d9a510b6172868a60798bba89` (2025-03-06); latest tag 0.2.6 | MIT; second notice for the fast-surface-nets-rs port; third-party PDFs in `refs/` with unclear rights | iOS 16, macOS 13; tools 5.8; language versions [6, 5], so a Swift 6 toolchain would pick Swift 6 mode (read from the manifest) | 0.x, one maintainer, 246 commits, none since March 2025 | Reference only. It adds Heightmap, swift-noise (Apache-2.0) and an IssueReporting runtime; its extractors rebuild whole volumes with no dirty-chunk API |
| [metal-by-example/metal-spatial-dynamic-mesh](https://github.com/metal-by-example/metal-spatial-dynamic-mesh) | `8b04589f51bae9b64d7f4356c14d5a544437c4a8` (2025-03-29) | Unlicense | iOS 18, macOS 15, visionOS 2; Swift 5 | 8 commits, no tags; a sample app of about 376 lines | Reference only. GPU compute `LowLevelMesh` updates on a SwiftUI timer; no collision, input, CPU path or lifecycle handling |

[Asset provenance](../../docs/asset-provenance.md) and the [inclusion inventory](preflight-inclusion-bom.md) are unchanged, because nothing was included.

## Risks and mitigations

| Risk | Evidence | Mitigation |
| --- | --- | --- |
| C's footprint grows about 3 MiB per restart | First run: 12.1–12.3 MiB growth from cycle 1 to 5 on both geometries, four consecutive deltas above 1 MiB, constant node counts | Epic 12's first task: reuse the scene and reset tiles, then measure the restart rows again under the unchanged budgets |
| C's interval rows are unproven | First run: iPad S share 0.50 and 0.64 % against 0.5 %; both iPhone 12 runs void after three attempts, idle share 0.503–1.182 %. SpriteKit intervals are quantized at 16.7 ms, so occasional 33.3 ms skips decide the share row. C was not run in the confirmation | Epic 12 entry risk: measure C on both geometries under the unchanged budgets after the footprint fix; frame pacing on hardware in Epic 08's pre-distribution check |
| No retained visuals for the 2D scope | The confirmation retained screenshots for A2 only | Review C's visible terrain change early in Epic 12 and retain the evidence |
| iPhone 12 p99 headroom of the `ARView` host, if 3D is reopened | A2 idle I p99 22.69–33.05 ms, above 25 ms in 4 of 5 confirmation attempts; in the first run 4 of 10 3D idle attempts on that geometry broke the row; the Spike 00 `RealityView` terrain held p99 20.0 ms in the confirmation session. Cause untested | A new decision record with new evidence, such as physical-hardware measurements or an idle comparison of `RealityView` and `ARView` hosts; never a budget change applied to these runs |
| Collision cost dominates any 3D scope and is unmeasured on devices | Host per-chunk p95 17.5–18.9 ms in the first run and 17.1–17.5 ms in the confirmation's counted runs, against the 12 ms physical target; maxima up to 39.6 ms in counted runs; per-shape cost did not fall with smaller chunks | Applies if 3D is reopened. Collision stays off the input and rule path and is coalesced; lag p95 stayed at or below 80.1 ms. Measure on hardware in Epic 08's pre-distribution checks. Parallel chunk jobs, a lower collision cadence (`collisionInterval`) or fewer, larger chunks are untried options |
| Hosted timing cannot rank candidates | On Xcode 26.6 and iOS 26.5 every hosted idle window broke the interval budgets and the full job exceeds its 180-minute timeout ([hosted run](../../experiments/dig-feasibility/evidence/hosted-run.txt)); builds and behaviour suites passed there | Use the hosted job for builds and behaviour; take timing comparisons from a calibrated local host |
| iOS 18.0 floor not executed | Typecheck and build only; no local iOS 18 runtime | Run the dig title on an iOS 18 runtime as part of ADR-003's distribution-readiness checks |
| Rule digests may differ across builds | `Float` heights; equality shown on one arm64 build | Before any feature compares digests across builds, add a cross-toolchain check or move rule state to integer depth units |
| Drag conflicts with shell scrolling | Shell `ScrollView` takes surface drags as digs | Epic 12 decides on a full-screen gameplay presentation in the shell; not a contract change |
| Simulator GPU is not representative | Apple's Simulator guidance | No compute path; device checks before release |
| First-run receipt verdicts are stale | `local-receipt.json`'s verdict block predates the void-exclusion logic and lists nine failed sprite rows, where the current verdicts list three | Read first-run verdicts from `local-measurements.json`, recomputed with `verify.py --summarize-only`; the confirmation's receipt and measurements were written by the current verifier and agree |

## Not measured

- Physical GPU work, presented frames, thermal behaviour, battery use and device memory pressure. Memory evidence is simulator `phys_footprint` snapshots and the process ledger peak.
- iOS 18.0 runtime behaviour; the floor is a typecheck and build boundary only.
- Hosted timing: every hosted run was void (see Toolchain); hosted CI covered builds and behaviour only.
- Release-build timing; Release was built, not measured.
- VoiceOver, Dynamic Type, rotation and background/foreground interruption.
- C in the confirmation session; its figures come from the first run only.
- The B window's interval statistics and the load window, which the per-run reports record and the retained summary omits.

## Next step

Spike 11 is complete for mobile simulator acceptance, and Epic 08 follows under the roadmap order. Epic 12 starts with 2D excavation and first removes C's restart footprint growth; reopening 3D needs a new decision record with new evidence. The hosted `dig_feasibility` job has not run.
