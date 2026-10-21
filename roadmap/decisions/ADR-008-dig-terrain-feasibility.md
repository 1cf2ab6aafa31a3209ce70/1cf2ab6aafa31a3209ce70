# ADR-008 — Dig terrain feasibility

**Date:** 2026-10-20. **Status:** Accepted. The first run left the scope choice open, so this record defined a confirmation run, which ran in protocol order on 2026-10-20. The unchanged Spike 00 baseline passed its interval rows on both geometries, A2 then missed the iPhone 12 sustained-window p99 row, and Epic 12 therefore starts with 2D excavation. [Spike 11](../spikes/11-dig-feasibility.md) is complete for mobile simulator acceptance.

## Context

Spike 11 asks for a dig mechanic that fits a measured workload on the supported simulator geometries, and whether a terrain title fits [module contract version 1](ADR-007-module-contract-v1.md) before Epic 09A adopts it. [ADR-002](ADR-002-platform-rendering-baseline.md) set the starting path: RealityKit with `MeshDescriptor`, static collision generated separately, and no low-level mesh or compute work without a measured budget miss. [ADR-003](ADR-003-simulator-mobile-foundation.md) limits evidence to iOS simulators with iPhone 12 and iPad (9th generation) geometry and an iOS 18.0 deployment floor.

The [experiment](../../experiments/dig-feasibility/README.md) registers one title-owned `DigModule` through the production `ModuleHost` and `ModuleShellView`. One Debug build carries four candidates, chosen by a launch argument. They share the session, rule loop, input gate, trace driver and instrumentation:

| Candidate | Field and chunks | Mesh update | Collision |
| --- | --- | --- | --- |
| A heightfield | 48 × 48 cells (49 × 49 vertices) in 16 chunks of 12 × 12 cells | `MeshDescriptor` and `MeshResource.generate` per dirty chunk | Per-chunk `ShapeResource.generateStaticMesh(positions:faceIndices:)` |
| A2 lowlevel | A's rules, input and collision | One CPU-written `LowLevelMesh` per fixed-topology chunk | As A |
| B voxel | 48 × 16 × 48 voxels in 9 chunks of 16³, face-culled cubes | `MeshDescriptor` | Per-chunk static mesh |
| C sprite | A's rules drawn top-down | 48 × 48 `SKTileMapNode` with ten depth bands | None; the rules look up cells |

A2 is the low-level variant ADR-002 allows only after a measured mesh-budget miss; in the recorded run A missed the 4.0 ms mesh row once. The workload, budgets, void rule and decision rule were fixed before any candidate run; the [audit](../audits/spike-11-dig-feasibility.md) restates them with their Spike 00 basis. A candidate passes only if every budgeted row passes on both geometries in both runs. If no 3D candidate passes, Epic 12 starts with the 2D fallback. The protocol also required the unchanged Spike 00 baseline to run first on the same host: if it broke the interval budgets, the host was not comparable, and any budget change had to be decided before the candidate runs.

## Decision

### Scope

This record maps the brief's three scopes onto the candidates. *Deformable 3D terrain* is volumetric removal with overhangs or tunnels (B). *Simplified 3D chunks* is a chunked heightfield surface with fixed topology and no overhangs or tunnels (A and A2). *2D excavation* is C: top-down depth bands with no physical response.

**Deformable 3D terrain is rejected.** B fails the correctness row on both geometries in all four runs. Its sphere carve undercuts sideways and opens controls 32 and 35 while their surface stays untouched, so it scores 26 after S and 30 after B instead of 24 and 28; the pure fixture test reproduces this. B also misses the mesh row in every run (5.5–5.9 ms p95 against 4.0). Neither failure depends on host noise.

**`MeshDescriptor` rebuilds are not the mesh path.** A's mesh p95 is 3.63–4.27 ms, nearly all main-actor `MeshResource.generate` for up to four chunks, and it missed the 4.0 ms row once. A2 performs the same update in 0.57–0.65 ms p95 with identical rules, input and collision.

**The first run left the choice between simplified 3D chunks (A2) and 2D excavation (C) open.** A2 passed every row in three of its four runs; its one miss was iPhone 12 run 1, S p99 26.7 ms against 25. Run after the candidates, the unchanged Spike 00 baseline measured terrain p99 29.3 ms on the iPhone 12 geometry and 21.6 ms on the iPad geometry, so the protocol ruled out that session's iPhone 12 interval rows. C missed its own rows: on the iPad geometry, 0.50 and 0.64 % of S intervals above 33.3 ms, and restart footprint growth of 12.31 and 12.25 MiB with four consecutive deltas above 1 MiB. Both its iPhone 12 runs stayed void after three attempts. This record therefore fixed a confirmation run that kept every budget unchanged:

1. In one host session, run the unchanged Spike 00 `PlatformBaseline` integration test once per geometry, first.
2. If the baseline passes every interval row on both geometries (p95 ≤ 20 ms, p99 ≤ 25 ms, at most 0.5 % of intervals above 33.3 ms), run A2 twice per geometry with `verify.py <new evidence directory> --candidate lowlevel --runs 2`. Retain the per-run reports' probe contact and rest records and one after-trace screenshot per geometry with that evidence.
3. If A2 then passes every row on both geometries in both runs, Epic 12 builds simplified 3D chunks on A2. Otherwise Epic 12 starts with C, as the brief requires, and first removes C's restart footprint growth.
4. If the baseline fails again, record that the host is not comparable. The lead then decides and records any budget change before A2 runs.

**The confirmation run selects 2D excavation.** It used the first run's host, toolchain and simulator runtime, and A2 ran at experiment source hash `b21815d8…`, which carries the current verifier. All numbers are simulator scene-update intervals.

- **Step 1, 17:17–17:22.** The unchanged baseline ran first. Its terrain window passed every interval row on both geometries: on the iPhone 12 geometry p95 16.9 ms and p99 20.0 ms, with 1 of 424 intervals above 33.3 ms; on the iPad geometry 16.7 and 21.9 ms, with 1 of 422. The gate read the terrain window, the Spike 00 window the interval rows rest on. The blocks and panel windows include mode entry and taps, so they are not comparable and were reported, not gated; the iPhone 12 blocks window measured p99 57.6 ms.
- **Step 2, 17:22–17:50.** A2 ran twice per geometry. On the iPad geometry both runs counted on their first attempt and passed every row. On the iPhone 12 geometry, run 1 counted on its second attempt and failed S p99 at 25.99 ms against 25.0. Run 2 stayed void after three attempts, with idle p99 27.53, 25.53 and 33.05 ms. The verifier's verdict is fail, with one failed row: iPhone 12 S p99. The retained probe records show first contact on the untouched surface and settles that follow the rule rest height down to the depth clamp; the screenshots show the excavated trenches.
- **Step 3 applies as written.** A2 did not pass every row on both geometries in both runs, so Epic 12 starts with C: SpriteKit `SKTileMapNode`, top-down depth bands over the heightfield rules. No budget changed. Epic 12 first removes C's restart footprint growth. C's other first-run misses, the iPad S share and the void iPhone 12 runs, are Epic 12 entry risks; C has not been measured since the first run.

**The iPhone 12 p99 miss is present without dig work.** On the iPhone 12 geometry, A2's idle window I, in which nothing digs, broke the 25 ms p99 row in 4 of 5 confirmation attempts (I p99 22.69–33.05 ms). In the first run, the 3D candidates' idle windows broke it in 4 of 10 attempts on that geometry; A2's own two passed at 24.72 and 24.58 ms. In the confirmation session, the Spike 00 `RealityView` terrain window held p99 20.0 ms on the same geometry. The module-retained `ARView` host's idle cost on that geometry is a likely contributor, but the two scenes also differ and the cause is untested. This is recorded as a limit and a risk. It does not discount the miss.

**Reopening 3D** for Epic 12 needs a new decision record with new evidence, for example physical-hardware measurements or an idle comparison of `RealityView` and `ARView` hosts. A budget change applied to these runs cannot reopen it.

### Renderer and mesh-update path

**2D, Epic 12's starting scope:** SpriteKit `SKTileMapNode` with depth-band tile groups and rule cell lookup, without collision. The `SKMutableTexture` fallback was not built. The prototype recreates its `SKScene` and `SKTileMapNode` on every reload, the likely cause of its restart footprint growth; reusing the scene and resetting tiles is the untried fix.

**3D, only if a later decision reopens it.** The path below is what these measurements support for simplified 3D chunks. It does not apply to Epic 12's starting scope.

- **Renderer:** RealityKit. The prototype hosts it in a module-retained `ARView` in non-AR camera mode; Spike 00 and the module seam used `RealityView`. Both fit contract version 1, and these measurements are for `ARView`.
- **Mesh:** one `LowLevelMesh` per fixed-topology chunk, written on the CPU. Indices and part bounds are written once, with bounds that cover the whole depth clamp; each update rewrites the interleaved position and normal buffer in one callback. Normals come from the global grid, so chunk seams match. Extraction runs off the main actor on a captured copy-on-write field. The app builds for an iOS 18.0 deployment target with no availability guards, so it uses no API above iOS 18.0; the iOS 27-only `LowLevelMesh` members are also absent from the CI SDK.
- **Collision:** per-chunk `ShapeResource.generateStaticMesh(positions:faceIndices:)` built from rule-derived CPU arrays with `UInt16` indices, never read back from the render mesh. A job generates its chunks serially off the main actor and installs the whole dirty set at once. The SDK has no heightfield collision shape, and a convex hull cannot represent a hole.
- **No Metal compute or custom renderer**, for measured reasons. In the first run A2's mesh update is 0.57–0.65 ms p95 while its collision is 18.1–18.8 ms p95 per chunk, so compute would speed up the cheap part. `generateStaticMesh` needs CPU arrays, so GPU-written vertices would need a read-back. Apple states that Simulator GPU behaviour does not represent devices. No iOS 26 or 27 API is used.

### Pending-geometry policy

Rules are authoritative; meshes and colliders are views of one field revision. `GeometrySync` and the shared rule loop implement the policy:

- Rules never wait for geometry. Ticks, digs, collection and score continue while builds are pending, and input is never blocked.
- Each lane, mesh and collision, has at most one job in flight. Dirty regions recorded meanwhile are unioned, and the next job builds the latest revision, so intermediate revisions are skipped. Only geometry work is coalesced; no accepted command is dropped.
- A finished job installs only if it is its lane's current job in the current rule generation and scene epoch. Restart starts a new generation and scene reload a new epoch, so late builds are refused. A failed build re-queues its region.
- A collision job installs its whole dirty set together, so chunk seams never mix revisions.
- Pause stops input and rule ticks and makes the sphere probes kinematic. A job that finishes while paused is discarded and its region re-queued for resume. Rules are never rolled back.
- Touch resolves by ray-marching the current rule field, never the possibly stale collider. Physics is presentation: the score never reads contacts or colliders.

The research workload asked for independent per-chunk collision jobs; the prototype runs one job per lane for the whole dirty set. Collision lag stayed within budget, at p95 57.6–80.1 ms and at most 90.5 ms against 100 and 250 ms in the first run, and at p95 76.0–77.0 ms and at most 92.9 ms in the confirmation's counted A2 runs.

### Determinism policy

- Rule state advances only on fixed 60 Hz ticks. Frame time accumulates as integer nanoseconds, each frame delta is clamped to 0.25 s, and pause discards frame time. Frame cadence decides how many ticks run, never what happens in them.
- Commands are `TimedInput<DigCommand>` and run in queue order on their tick. Touch, the accessible controls and the trace driver submit through one session gate, and a command takes the tick that is current when it is accepted.
- No mesh, collision, physics or timing value enters rule state. An item is collected on the first tick its centre is open in the rule field.
- The outcome identity is a digest of field contents, revision, score and collected set. It excludes tick stamps, which depend on when commands arrive. For tick-stamped traces, host tests also match the full digest, ticks included, across frame cadences.
- Equality is shown within one build on arm64. Rule state uses `Float` heights rather than the integer depth units the research proposed, so identity across compilers, architectures or the CI toolchain is unverified. Anything that compares digests across builds needs that check first.

### Contract outcome

Version 1 carries the terrain title unchanged. `Packages` has no diff against `edfd936`, `scripts/check-foundation.py` passes, and no RealityKit, SpriteKit or `DigCore` type crosses `GameModule` or `ModuleSession`. Epic 07's owners make no version 1 change before Epic 09A adopts it. The title uses existing members:

| Need | Version 1 member |
| --- | --- |
| Suspend input, rule ticks and physics | `ModuleSession.playing` |
| Full restart from the initial rule state | `prepare(for:)` and `begin(for:)` |
| Renderer that survives the shell's loading screen | Module-retained view behind `makeGameplay()` |
| Pause control | `ModulePlayContext.pause` |
| Reduced motion for the 2D collection animation | `setReducedMotion(_:)` |
| Score by level | `recordSuccess(in:)` |

One shell observation is not a contract gap. `SharedShellView` places gameplay inside a vertical `ScrollView`, so a drag that starts on the dig surface digs rather than scrolls; the UI tests scroll below the surface. If Epic 12 wants full-screen gameplay, that is a shell presentation option, not a version 1 member change.

### Dependencies

- **[Voxels](https://github.com/heckj/Voxels) at `bf3fe67`: reference only, not a dependency.** It is MIT, with a second notice for its surface-nets port and third-party PDFs of unclear redistribution rights in `refs/`. It is a 0.x library with one maintainer and no commit since March 2025. It brings Heightmap, swift-noise (Apache-2.0) and an IssueReporting runtime, and its manifest would select Swift 6 mode on a Swift 6 toolchain. Its extractors rebuild whole volumes with no dirty-chunk API; the research extrapolates its upstream benchmark to roughly 5–7 ms per 16³ chunk. B uses original extraction.
- **[metal-spatial-dynamic-mesh](https://github.com/metal-by-example/metal-spatial-dynamic-mesh) at `8b04589`: reference only.** It is under the Unlicense, but it is a visionOS-oriented sample app of about 376 lines, not a library. It updates a `LowLevelMesh` with GPU compute on a SwiftUI timer and has no collision, input, CPU update path or lifecycle handling.
- No candidate code, test, asset or tooling was copied. [Asset provenance](../../docs/asset-provenance.md) and the [inclusion inventory](../audits/preflight-inclusion-bom.md) are unchanged.

## Alternatives

- **Accept A2 by relaxing the p99 budget**, or by treating its iPhone 12 misses as host noise. Rejected: it changes a budget after seeing the runs, which the test plan forbids. The confirmation baseline passed on the same host, so the protocol gives no ground to set the iPhone 12 rows aside. The idle-window observation under [Scope](#scope) is recorded as a risk and does not change the result.
- **Run A2 again.** Rejected: its iPhone 12 run 1 counted and failed S p99, so no further run can make A2 pass every row in both runs under this protocol.
- **Choose 2D from the first run alone.** Rejected at the time: the protocol ruled out that session's iPhone 12 interval rows, and C missed its own rows. The confirmation run reached 2D through the protocol instead.
- **Move `MeshDescriptor` resource creation off the main actor** with the iOS 18 nonisolated async `MeshResource(from:)`. Not built: A2 already removes the main-actor cost.
- **Smoother voxel extraction** (surface nets, greedy meshing, collision proxies). Not tried. It would not fix B's correctness failure, which comes from the brush, and it is engine work outside the timebox.
- **Metal compute or a custom renderer.** Declined for the measured reasons above.

## Evidence and limits

The [audit](../audits/spike-11-dig-feasibility.md) records source identity, the fixed workload and budgets, per-geometry tables, the confirmation run and risks. Both runs used a Mac14,6 (Apple M2 Max) host on macOS 27.2, Xcode 27.1 (`27A9275`) and iOS Simulator 26.0 (`23A5287g`), with Debug builds at `-O` carrying DEBUG instrumentation.

- **First run:** [receipt](../../experiments/dig-feasibility/evidence/local-receipt.json), [measurements](../../experiments/dig-feasibility/evidence/local-measurements.json), [calibration](../../experiments/dig-feasibility/evidence/spike00-calibration.txt) and [idle windows](../../experiments/dig-feasibility/evidence/local-idle-windows.txt), which list every attempt, void ones included. The receipt's verdict block predates the verifier's exclusion of runs still void after their repeats; the measurements, recomputed with `verify.py --summarize-only`, carry the current verdicts. All 28 pure tests, all 24 app-hosted and behaviour tests per geometry and every timing invocation passed, with no XCTest retry.
- **Confirmation run:** baseline [calibration](../../experiments/dig-feasibility/evidence/confirm-calibration.txt), per-attempt [idle and sustained windows](../../experiments/dig-feasibility/evidence/confirm-windows.txt), [measurements](../../experiments/dig-feasibility/evidence/confirm-measurements.json) and [receipt](../../experiments/dig-feasibility/evidence/confirm-receipt.json), which agree because the current verifier wrote both, the counted runs' [probe records](../../experiments/dig-feasibility/evidence/confirm-probes.json), and one after-trace screenshot per geometry ([iPhone 12](../../experiments/dig-feasibility/evidence/confirm-iphone12-lowlevel-after-trace.png), [iPad](../../experiments/dig-feasibility/evidence/confirm-ipad9-lowlevel-after-trace.png)). All 28 pure tests, the 7 app-hosted and behaviour tests that apply to A2 per geometry and every timing invocation passed, with no XCTest retry.

All timings are scene-update callback intervals and `ContinuousClock` CPU or wall time on the simulator host; memory is `phys_footprint` snapshots and the process ledger peak. They rank candidates on this host only. They are not presented frames or device results, and they neither meet nor replace ADR-002's physical targets: presented-frame p95 ≤ 20 ms and p99 ≤ 33.4 ms, peak footprint ≤ 250 MiB, mesh p95 ≤ 4 ms and collision p95 ≤ 12 ms on the A14 and A13. The host's per-chunk collision p95 of 17.5–18.9 ms in the first run already exceeds the 12 ms physical target, so collision cost is the first device risk if 3D is reopened. Physical GPU, presented frames, thermal, battery, device memory pressure, the iOS 18 runtime and hosted CI are unmeasured; the `dig_feasibility` workflow job exists but has not run.
