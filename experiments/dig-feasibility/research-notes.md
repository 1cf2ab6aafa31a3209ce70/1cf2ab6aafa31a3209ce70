# Spike 11 research notes: renderer guidance, external candidates, fixed workload and budgets

Researcher notes for the Spike 11 team, written on 2026-10-20 at `edfd936` before any candidate run and retained unchanged apart from this paragraph. The external clones were read only: nothing in them was built or run, and no code was copied. The [audit](../../roadmap/audits/spike-11-dig-feasibility.md) restates the workload and budgets that the runs used and records where the prototype deviated from them.

**Environment observed for this research**

- Host: Apple M2 Max, 32 GiB, 12 cores, macOS 27.2 (`26B5112a`).
- Toolchain: Xcode 27.1 (`27A9275`) with the iPhoneSimulator 27.1 SDK.
- Simulator runtimes installed: iOS 17.4 (`21E213`) and iOS 26.0 (`23A5287g`). No iOS 18 runtime is installed locally. Hosted CI has a separate iOS 18.0 (`22A3351`) minimum-runtime job in `.github/workflows/mobile.yml`.
- Comparison with Spike 00: Spike 00 ran on macOS 27.0 (`26A428`) with Xcode 27.0 (`27A266a`), and its host chip was not recorded. The host has therefore changed since the baseline. See the calibration step in section 3.

---

## 1. Apple renderer guidance (rechecked 2026-10-20)

### SDK availability (installed SDK, read directly from the swiftinterface)

`RF` stands for `/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator27.1.sdk/System/Library/Frameworks/RealityFoundation.framework/Modules/RealityFoundation.swiftmodule/arm64-apple-ios-simulator.swiftinterface`. Its SHA-256 prefix is `c9a6788a2e6a9f9c`.

| API | iOS floor | Isolation / shape | Location |
|---|---|---|---|
| `MeshDescriptor` | 15.0 | struct | `RF`:7612 |
| `MeshResource.generate(from: [MeshDescriptor])` | 15.0, not deprecated | `@MainActor`, sync | `RF`:8751 |
| `MeshResource.generateAsync(from:)` and `replaceAsync(with:)` | 15.0, **deprecated 18.0** | `LoadRequest` | `RF`:8737–8757 |
| `MeshResource.init(from: [MeshDescriptor]) async`, `replace(with: Contents) async` | **18.0** | **nonisolated** async, so it can run off the main actor | `RF`:8805–8809 |
| `LowLevelMesh` (Descriptor, Attribute, Layout, Part, `withUnsafeMutableBytes`, `replace(bufferIndex:using:)`, `replaceIndices(using:)`, `parts.replaceAll`) | **18.0** | `@MainActor` class | `RF`:10661–10757 |
| `LowLevelMesh` `instanceCapacity`, `allowsPrimitiveRestart`, `Layout.stepFunction/stepRate` | **27.0** | n/a | `RF`:10693–10722 (for example 10705) |
| `MeshResource(from: LowLevelMesh)` sync and async, `lowLevelMesh` | 18.0 | `@MainActor` | `RF`:10790–10797 |
| `ShapeResource.generateStaticMesh(positions: [SIMD3<Float>], faceIndices: [UInt16]) async throws` | **18.0** | nonisolated async; **UInt16 indices**, so fewer than 65,536 vertices per shape | `RF`:14026–14029 |
| `ShapeResource.generateStaticMesh(from: MeshResource) async throws` | 18.0 | `@MainActor` async | `RF`:14030–14033 |
| `ShapeResource.generateConvex(from:)` sync and nonisolated async | Enclosing extension is iOS 13.0, with no member annotation (docs also say 13.0) | n/a | `RF`:13995–14012 |
| Heightfield collision shape | **None in the SDK** (grep for `eightfield` finds nothing) | n/a | n/a |
| `MeshInstancesComponent` | 26.0 | n/a | `RF`:12461 |
| `MeshDeformerComponent` and the deformer stack | 27.0 | n/a | `RF`:456, 13189–13319, 14509–14568 |
| `NavigationMeshComponent` | 27.0 | n/a | `RF`:16056 |
| `SceneEvents.Update` | 13.0 | n/a | `RF`:7795–7799 |
| `RealityView` | 18.0 | n/a | `.../_RealityKit_SwiftUI.framework/Modules/_RealityKit_SwiftUI.swiftmodule/arm64-apple-ios-simulator.swiftinterface`:384–386 |

**SpriteKit headers** (`.../iPhoneSimulator27.1.sdk/System/Library/Frameworks/SpriteKit.framework/Headers/`):

- `SKMutableTexture`: iOS 8.0 (`SKMutableTexture.h`:15). `modifyPixelDataWithBlock` is at :37; Swift also offers an async alternative.
- `SKPhysicsBody bodyWithTexture:alphaThreshold:size:`: iOS 8.0 (`SKPhysicsBody.h`:94).
- `SKTileMapNode`: iOS 10.0 (`SKTileMapNode.h`:18). `setTileGroup:forColumn:row:` is at :176.
- `SKView.preferredFramesPerSecond`: iOS 10.0 (`SKView.h`:84).

**Typecheck proof.** I wrote my own probe under `.../scratchpad/spike11/apiprobe/`; no candidate code was used. `Floor18.swift` exercises LowLevelMesh (descriptor, CPU write, parts, GPU `replace(bufferIndex:using:)`), `MeshResource(from: LowLevelMesh)`, the async `MeshResource(from: [MeshDescriptor])`, async `replace(with:)`, both `generateStaticMesh` overloads, async `generateConvex`, `SKMutableTexture` and `SKPhysicsBody(texture:alphaThreshold:size:)`.

- Command: `xcrun swiftc -swift-version 5 -sdk <iPhoneSimulator27.1.sdk> -target arm64-apple-ios18.0-simulator -typecheck`
- `Floor18.swift`: exit 0 with 2 warnings (log in `floor18.log`).
- `Above18.swift` fails as expected: "'MeshDeformerComponent' is only available in iOS 27.0 or newer" and "'MeshInstancesComponent' is only available in iOS 26.0 or newer".
- Compiling at the floor is a build boundary only. It does not show that the code runs on iOS 18.

### developer.apple.com (fetched 2026-10-20)

- **LowLevelMesh** ([doc](https://developer.apple.com/documentation/realitykit/lowlevelmesh)): iOS/iPadOS 18.0, macOS 15.0, visionOS 2.0, tvOS 26.0. The page says: "Use `LowLevelMesh` when you want to bring your own vertex format to RealityKit or update your data frequently … either use Swift for CPU processing, or Metal Compute Shaders for GPU processing." Its note adds: "Use `MeshDescriptor` for a simpler alternative to `LowLevelMesh`."
- **Creating a plane with low-level mesh** ([article](https://developer.apple.com/documentation/realitykit/creating-a-plane-with-low-level-mesh)):
  - Per-frame vertex changes are "inefficient without direct access to the underlying GPU buffers".
  - "Loop over the vertices within the withUnsafeMutableBytes callback for best performance, as calling this method repeatedly is costly".
  - Part bounds must enclose every vertex, or RealityKit may cull the mesh.
- **Generating interactive geometry with RealityKit** ([sample](https://developer.apple.com/documentation/realitykit/generating-interactive-geometry-with-realitykit)):
  - Per-frame GPU compute updates of a LowLevelMesh and LowLevelTexture to "simulate the appearance of fabric, terrain, or water".
  - Its collider is a fixed flat box created once and never regenerated.
  - Page metadata lists macOS 15 and visionOS 2 only, with no iOS entry.
- **MeshDescriptor** ([doc](https://developer.apple.com/documentation/realitykit/meshdescriptor)): iOS 15.0. It is the documented path for mesh construction (`MeshResource.generate(from:)`).
- **MeshResource** ([doc](https://developer.apple.com/documentation/realitykit/meshresource)): `generateAsync` and `replaceAsync` are marked deprecated. `replace(with:)` and `init(from:)` are current.
- **`generateStaticMesh(positions:faceIndices:)`** ([doc](https://developer.apple.com/documentation/realitykit/shaperesource/generatestaticmesh(positions:faceindices:))): iOS 18.0.
  - "The triangle mesh is pre-processed into an optimized format … can take significant time if the position counts are large … the position count should be as small as possible."
  - The shape works with `PhysicsBodyMode.static` only and cannot be used as a trigger.
- **`generateStaticMesh(from:)`** ([doc](https://developer.apple.com/documentation/realitykit/shaperesource/generatestaticmesh(from:))): iOS 18.0. Apple's example wraps it in `Task(priority: .low)` "because generating collision meshes can take a while". Static mode only.
- **`generateConvex(from:)` async** ([doc](https://developer.apple.com/documentation/realitykit/shaperesource/generateconvex(from:)-6upj9)): iOS 13.0. It produces the convex hull and advises small vertex counts. A hull cannot represent a concave hole, so it is only usable as a coarse proxy.
- **RealityKit updates** ([page](https://developer.apple.com/documentation/updates/realitykit)):
  - June 2024: "Use LowLevelMesh to efficiently bring your mesh data to RealityKit …".
  - June 2025: MeshInstancesComponent.
  - No collision-generation changes are listed. The page has no 2026 section, although the SDK has iOS 27 deformer APIs.
- **Metal in Simulator** ([doc](https://developer.apple.com/documentation/metal/developing-metal-apps-that-run-in-simulator)):
  - "Simulator doesn't try to exactly simulate the GPU … directs them to the selected GPU on the host Mac."
  - It exposes roughly Apple GPU family 2 capabilities, with no Xcode memory or performance measurement.
  - "Don't use Simulator to design your iOS, tvOS, or visionOS rendering engine."
- **SKMutableTexture** ([doc](https://developer.apple.com/documentation/spritekit/skmutabletexture)): iOS 8.0. "Because there is a performance penalty for updating the texture's contents, consider other options first", for example `texture(from:)` or a node tree.
- **`SKPhysicsBody(texture:alphaThreshold:size:)`** ([doc](https://developer.apple.com/documentation/spritekit/skphysicsbody/init(texture:alphathreshold:size:))): iOS 8.0. "Fine details may be ignored if keeping them would cause a significant performance penalty."

### Renderer conclusions

1. **Keep RealityKit with `MeshDescriptor` as the default mesh path.** It is floor-compatible and matches the Spike 00 baseline instrumentation. Use the nonisolated async `MeshResource(from: [MeshDescriptor])` or async `replace(with:)` (iOS 18) to move resource creation off the main actor if the main-actor share shows up in scene-update intervals.
2. **LowLevelMesh** (iOS 18.0, at the floor) is permitted as one narrow variant: CPU in-place `withUnsafeMutableBytes` on fixed-topology heightfield chunks. Build it **only if** the `MeshDescriptor` path misses the per-command mesh CPU budget. That is ADR-002's rule: no low-level work without a measured miss. Do not use its iOS 27-only members. They are above the floor and absent from the CI SDK (Xcode 26.6).
3. **Do not build a Metal compute path in this spike.**
   - In the Spike 00 baseline, mesh generation (1.0–1.39 ms) is about 10–15× cheaper than collision (14.4–19.3 ms). Compute speeds up only the cheap part.
   - `generateStaticMesh` needs CPU arrays or a MeshResource, so GPU-written vertices would need a read-back to stay collidable.
   - Apple states that Simulator GPU behaviour is not representative. Any compute timing on this host would be uninterpretable for the A14 (iPhone 12) or A13 (iPad 9th generation).
   - Record this as a measured-reason decline under ADR-002 and Spike 11 item 5.
4. **Collision is the constraint.**
   - No heightfield shape exists, and convex hulls cannot represent holes.
   - Use per-chunk `generateStaticMesh(positions:faceIndices:)` built from rule-derived CPU arrays, never read back from the render mesh. This is what Spike 00 does.
   - Run at most one regeneration in flight per chunk, with the latest request winning, and keep it out of the input and rule path.
   - Keep each chunk under 65,536 vertices (UInt16 indices).
5. **Use SpriteKit for the 2D approximation.** Prefer `SKTileMapNode` with depth-band tile groups (iOS 10), following Apple's `SKMutableTexture` caution. Use `SKMutableTexture` only if banding is unreadable. `SKPhysicsBody(texture:)` is needed only for a side-view variant, which is not in the fixed workload.
6. **Use iOS 26 and 27 APIs nowhere.** MeshInstancesComponent, MeshDeformerComponent and NavigationMeshComponent are above the 18.0 floor, and the iOS 27 ones are absent from the CI SDK.

---

## 2. External candidates (read-only clones)

### heckj/Voxels: recommendation **reference-only** (not a dependency)

**Clone and maintenance**

- Clone: `.../scratchpad/spike11/external/voxels/Voxels`.
- HEAD: `bf3fe6767497c55d9a510b6172868a60798bba89` on `main`, committed 2025-03-06 ("aligning the weird IssueReporting thing…").
- Tags: 0.1.0 (2024-09-11) through **0.2.6 (2024-11-23, latest release)**. HEAD is 5 commits past 0.2.6.
- 246 commits. Activity peaked in Aug–Sep 2024, followed by 1 commit in 2025-03 and none in the 19 months since.
- GitHub: 18 stars, 1 open issue, not archived, single maintainer.
- Version 0.x, and the repo carries an api-breakage workflow, so the API is not stable.

**License and notices**

- MIT, © 2024 Joseph Heck.
- `SurfaceNetRenderer` is "ported and updated (derived)" from fast-surface-nets-rs (MIT, © 2021 bonsairobo), so a second notice applies.
- A commented-out file cites RealityGeometries (MIT).
- `refs/` contains third-party PDFs (a dual contouring paper and a Medium article export) with unclear redistribution rights.

**Platforms and language mode**

- `Package.swift` declares swift-tools 5.8, iOS 16 and macOS 13. That is below our 18.0 floor, so compatible.
- It declares `swiftLanguageVersions: [.version("6"), .v5]`, and `.swift-version` is 5.10. A Swift 6 toolchain would select Swift 6 mode. This is inferred from the manifest and was not built.
- Upcoming and experimental features: ExistentialAny, InternalImportsByDefault, AccessLevelOnImport.
- CI: Ubuntu for the library; Xcode 15.4 on macOS for the example app.

**Dependencies (library target)**

- `heckj/Heightmap` from 0.6.0 (MIT, last pushed 2025-03-06), which depends on `tayloraswift/swift-noise` (**Apache-2.0**).
- `pointfreeco/xctest-dynamic-overlay` from 1.5.0. Its product is IssueReporting (MIT), which is runtime code that calls `reportIssue` from library paths.
- `apple/swift-docc-plugin` (a plugin).
- The benchmarks `Package.resolved` adds package-benchmark, jemalloc, hdrhistogram and others (benchmark-only).
- No network code in `Sources` (grep).

**API shape**

- *Storage:*
  - `VoxelAccessible<Element>: Collection` (`value(_:) throws`, `bounds`, `subscript`) and `VoxelWritable` (`set`).
  - `VoxelArray<T: Sendable>` is dense and backed by an array over `VoxelBounds`. Its setter uses an unchecked linearize plus `precondition`.
  - `VoxelHash<T>` is sparse, a `[VoxelIndex: T]` dictionary.
  - `VoxelUpdate<T>` batches are applied by `VoxelArray.updating(with:)`.
  - `VoxelScale<Float>` maps between positions and indices. `HeightmapConverter` builds voxels from a Heightmap, and there are `SDF` helpers.
- *Surface extraction:*
  - `SurfaceNetRenderer().render(_:scale:within:) -> MeshBuffer` is naive Surface Nets on SDF values. It resets dictionary caches on every call, and chunks need 1-voxel padding.
  - Also available: `MarchingCubesRenderer.render(_:scale:within:adaptive:)`, `BlockMeshRenderer.render(_:scale:within:surfaceOnly:filter:)`, `fastBlockMeshByLayers` and `GreedyBlockMesh`.
- *Mesh updates:*
  - `MeshBuffer` (positions, normals, `[UInt32]` indices) converts to `meshDescriptor()` under `#if canImport(RealityKit)`. The caller then calls `MeshResource.generate`.
  - Every call is a full rebuild. There is no dirty-region or incremental API, no LowLevelMesh and no collision.

**Upstream benchmarks (not ours, unverified)**

- Source: `Benchmarks/0.2.6.md`, run on an M1 MacBook Pro under macOS (Darwin 24.3).
- SurfaceNet over 101×51×101 bounds: 604 ms. Marching cubes: 614 ms. Block surface: 156 ms.
- 604 ms over about 520k cells is roughly 1.2 µs per cell. A 16³ chunk (about 4.1k cells, or 5.8k sampled with padding) would take roughly 5–7 ms, and the 4 dirty chunks per command in this workload would take about 20–28 ms. That is well over the 4 ms per-command budget below.
- Treat this only as a sizing hint. It is not a measurement of this workload.

**Recommendation: reference-only.** Under ROADMAP rule 10 and the privacy contract's "Before adding a dependency", adoption would bring the following for a roughly 4 kLOC 0.x library that has been dormant since 2025-03:

- 3+ transitive packages under mixed MIT and Apache-2.0 terms, plus an IssueReporting runtime.
- Two derived-work notices.
- Third-party PDFs.
- Swift 6 mode.

Its extraction has no incremental chunk API, and the upstream numbers suggest it misses the budget at this chunk size. Use it as an algorithm and API-shape reference only: Surface Nets with chunk padding, block and greedy meshing, the `VoxelBounds`/`VoxelScale` naming. If the voxel candidate is benchmarked, write an original fixed-size array chunk extractor. Copy no code. Any later inclusion needs a new review and an inclusion-BOM entry.

### metal-by-example/metal-spatial-dynamic-mesh: recommendation **reference-only**

**Clone and maintenance**

- Clone: `.../scratchpad/spike11/external/dynamic-mesh/metal-spatial-dynamic-mesh`.
- HEAD: `8b04589f51bae9b64d7f4356c14d5a544437c4a8` on `master`, committed 2025-03-29 ("Fixed errors due to missing @MainActor annotations").
- 8 commits in total: 7 on 2024-06-11 and 1 on 2025-03-29. No tags or releases.
- GitHub: 107 stars, 0 open issues, not archived.

**License:** Unlicense (public-domain dedication, no notice obligation).

**Platforms and language mode (from the pbxproj)**

- iOS 18.0, macOS 15.0, visionOS 2.0; `SUPPORTED_PLATFORMS` covers iphoneos/simulator, macosx and xros/simulator.
- `SWIFT_VERSION = 5.0`.
- The Info.plist sets the preferred scene role to volumetric (visionOS-oriented). Entitlements are empty.

**Dependencies:** none (Metal and RealityKit only). The repo is about 376 lines: Swift, a `.metal` file and a bridging header.

**API shape**

- `AnimatedWaveMesh` (`@MainActor`) builds a `LowLevelMesh.Descriptor` from `MemoryLayout` offsets of an interleaved vertex (position, normal, uv). It uses one layout and fixed capacities from `maxSegmentCount = 128`.
- `update(_:)` encodes compute passes. They write vertices through `lowLevelMesh.replace(bufferIndex: 0, using: commandBuffer)` and, on topology changes, indices through `replaceIndices(using:)` plus `parts.replaceAll` with fixed bounds.
- It uses non-uniform dispatch only if `supportsFamily(.apple4)`. That matters because Simulator reports roughly Apple2-family capability.
- Display goes through `MeshResource(from: lowLevelMesh)`.
- The update cadence is a 60 Hz SwiftUI `Timer` plus the `RealityView` `update:` closure. That ties mesh work to SwiftUI invalidation, so do not follow this pattern.
- There is no collision, no input, no CPU-update path and no lifecycle handling.

**Recommendation: reference-only.** It is a sample app, not a library, so there is nothing to depend on. Its GPU path cannot be measured meaningfully in Simulator, and it does not address collision, which is the dominant cost. Apple's LowLevelMesh documentation covers the same API. Use it only as a reading aid for descriptor, parts and bounds handling if the LowLevelMesh CPU variant becomes necessary. CONTRIBUTING still forbids copying any candidate code without a new inclusion review, even though the license would permit it.

---

## 3. Fixed workload (set before any comparison run)

### Common to all candidates

- **Host calibration first.** Before any candidate run, run the unchanged Spike 00 `PlatformBaseline` integration test once per geometry on the current host and toolchain.
  - Compare terrain p95/p99/share and the mesh and collision samples with the accepted values.
  - If the unchanged baseline itself breaks the interval budgets below, the host is not comparable. Stop, record it, and make any budget change as an explicit decision before candidate runs, never after.
- **Arena:** 1.6 × 1.6 scene units (su), from Spike 00 `TerrainHeightfield(width: 1.6)`. Maximum dig depth is 0.45 su (Spike 00 clamp). Use Spike 00's camera framing and directional light.
- **Rule state:**
  - Foundation-only and title-owned (ADR-006/007), advanced only by commands and never by frame time.
  - 48 × 48 cells, each 1.6/48 ≈ 0.0333 su; this is half the Spike 00 spacing of 0.0667 su.
  - Depth is stored as integer units of 0.001 su. Brush falloff comes from a precomputed integer table over cell offsets.
  - Each command increments a revision.
- **Dig command:**
  - Position in tenth-cell fixed point.
  - Brush radius 0.12 su, which is 3.6 cells. That keeps Spike 00's cell-relative radius (0.24 su over 0.0667 su = 3.6 cells).
  - Centre deepening of 0.02 su (20 units) per command with linear falloff. Spike 00 used 0.08 su per discrete drill; continuous input uses smaller stamps.
  - The touch hit-test resolves against the rule state, not the collider. Ray-march the rule heightfield, or the rule voxel surface for the voxel candidate. Input therefore never depends on a lagging collider.
- **Trace:** fixed and deterministic. It is a developer fixture, never a production save (bundled-content guide and privacy contract).
  - **S (sustained), 600 commands:** six serpentine rows at z = 4, 12, 20, 28, 36, 44 cells. Each row has 100 stamps from x = 4.0 to 43.6 cells in steps of 0.4 cells. Rows 12 and 36 lie on heightfield chunk boundaries.
  - **B (burst), 300 commands:** rows 20 and 28 again (200 stamps), then a column at x = 24 from z = 4.0 to 43.6 (100 stamps). Where the column crosses trenches 20 and 28, the depth reaches the clamp.
  - Expected centreline depth after S is about 0.18 su: 17 overlapping stamps × 20 units × mean falloff about 0.53. The pure model's golden value is authoritative.
- **Collectibles: 36 in total**, rule-owned at fixed cells. One is collected when the rule depth at its cell reaches **0.10 su (100 units)** or more.
  - 24 on trench centrelines (x = 10, 18, 30, 38 on each of the six rows).
  - 4 on ridges under the burst column (x = 24; z = 8, 16, 32, 40).
  - 8 controls never touched by any stroke (x ∈ {8, 40} × z ∈ {8, 16, 32, 40}; at least 4 cells from any stroke, against a 3.6-cell radius).
  - **Expected score: 24 after S and 28 after B, with the 8 controls never collected.** A pure fixture test asserts this per candidate before any timing run. If a candidate's brush gives a different set, fix the threshold or trace then, not after measuring.
- **Physics (3D candidates only):**
  - Each collectible is a dynamic sphere of radius 0.03 su with restitution 0 and friction 0.8. Horizontal translation and rotation are locked, as in the Spike 00 probe.
  - Physics is presentation only. Score never reads contacts or colliders.
- **Delivery through UI tests:**
  - The test launches with DEBUG-only arguments for the candidate and trace ID, taps one accessible "Run trace" control, and waits for a status element such as `dig.trace.done`.
  - An in-app driver issues command *k* at t₀ + k/rate on `ContinuousClock`, through the same gated `ModuleSession` input path that touch and accessible controls use.
  - Only one synthesized gesture enters the measured run, which limits exposure to N06/N09/N10. Existing retry classification applies.
  - Freehand drag, pause/resume, rotation and accessibility run in separate correctness tests, not inside timing windows (Spike 00 protocol precedent).
- **Windows per candidate, geometry and run:**
  - *Load:* from session begin to the first fully installed scene. Recorded only.
  - *Warm-up:* 5 s, excluded.
  - *I (idle control):* 10 s with no commands, about 600 intervals. This is the within-run host noise floor.
  - *S:* 60 s, 600 commands at **10 commands/s**, about 3,600 intervals. This equals the Spike 00 HUD ring capacity.
  - *B:* 10 s, 300 commands at **30 commands/s**, about 600 intervals. It exercises coalescing.
  - *Settle:* at most 15 active seconds (Spike 00 protocol cap), then assert score 28 and the collected set.
  - *R (restart) × 5:* restart, measure reload, replay the first 100 commands of S at 10/s, settle, idle 2 s, then snapshot footprint and entity/subscription counts.
  - Split these into two UI test cases: load through settle takes about 100 s, and restart cycles about 90 s. That keeps each under the repository's 180 s per-case allowance.
  - Run twice per geometry per candidate, and report each run separately and combined. That is 3 candidates × 2 geometries × 2 runs, about 12 × 3.5 min.
- **Cadence and determinism checks**, run separately from timing:
  - Pure tests replay the trace with commands batched 1, 2 and 6 per tick and assert identical final rule-state hashes and score.
  - In the app, repeat the trace with a DEBUG mesh-install delay of +50 ms and collider-install delay of +200 ms. For the 2D candidate, also run with `SKView.preferredFramesPerSecond` at 30 and 60. Assert identical score and collected set.
- **Instrumentation:** reuse the Spike 00 methods.
  - Scene-update intervals: `SceneEvents.Update` for RealityKit, `SKScene.update` for SpriteKit. Break the timestamp chain on pause; use nearest-rank percentiles; count intervals above 0.0333 s. That threshold counts every doubled 60 Hz interval.
  - Mesh and collision timing: `ContinuousClock`.
  - Footprint: `task_vm_info.phys_footprint`, a snapshot, not a peak.
  - Per command, record: ordinal, accept time, dirty chunks, mesh ms (total and the main-actor part), each collision job's ms, collision lag and coalesced count. Store these as local XCTest attachments only.
- **Integration:** the trace driver, renderer, physics and hit-testing stay title-owned. Neither the workload nor the budgets add any type to `GameCore` or the `GamePlatform` contract.

### Per candidate

| | A. Heightfield (RealityKit) | B. Voxel chunks (RealityKit) | C. 2D excavation (SpriteKit, top-down) |
|---|---|---|---|
| Arena | 1.6 × 1.6 su, depth ≤ 0.45 su | 1.6 × 1.6 su; 16 layers = 0.533 su, removable to 0.45 su (bedrock below) | 1.6 × 1.6 su rule arena fitted to the viewport like the Spike 00 board |
| Resolution | 49 × 49 vertices (2,401 vertices, 4,608 triangles) over 48 × 48 cells | 48 × 48 × 16 voxels of 0.0333 su; Int16 density lattice 49 × 17 × 49 (40,817 samples) | 48 × 48 rule cells; `SKTileMapNode` 48 × 48 tiles with 10 depth bands of 0.045 su (fallback: `SKMutableTexture` 192 × 192) |
| Chunking | 4 × 4 = 16 chunks of 12 × 12 cells (13 × 13 = 169 vertices, 288 triangles); normals from the global grid | 3 × 3 × 1 = 9 chunks of 16³ voxels (18³ padded samples); about 512 triangles per chunk when flat | None; dirty tile rectangle |
| Brush | Radius 0.12 su (3.6 cells), 0.02 su centre, linear falloff | 3D linear density decrement, radius 0.12 su, about 0.02 su centre deepening, centred on the rule surface point (permits undercut) | Same rule brush as A |
| Dirty set per command | At most 2 × 2 chunks, at most 676 vertices and 1,152 triangles (the Spike 00 size: 625 vertices, 1,152 triangles) | At most 2 × 2 chunks (diameter 7.2 < 16) | At most 8 × 8 = 64 tiles |
| Collision | Per-chunk `generateStaticMesh(positions:faceIndices:)` from rule arrays | Per-chunk static mesh from extracted triangles | None; rule cell lookup (presentation: drop animation, disabled under Reduce Motion) |
| Dig rate | S: 10/s; B: 30/s | S: 10/s; B: 30/s | S: 10/s; B: 30/s |
| Collectibles | 36 (24 / 4 / 8) | 36 | 36 |
| Run duration and windows | Warm-up 5 s, I 10 s, S 60 s, B 10 s, settle ≤ 15 s, R × 5 | Same | Same |
| Limits recorded | No overhangs or caves | Overhang lips only from undercut; extraction cost unknown | No 3D view and no physical response to geometry |

---

## 4. Simulator budgets (fixed now; each rests on a named baseline observation)

**Scope.** These budgets apply to each geometry and candidate on the iOS 26.0 simulator on the recorded host. They are pass/fail thresholds for comparing candidates in this environment only.

**Simulator budgets do not approve, replace or weaken physical budgets.** The ADR-002 and Spike 00 README physical targets remain unvalidated workload goals: presented-frame p95 ≤ 20 ms and p99 ≤ 33.4 ms, peak footprint ≤ 250 MiB for tiny terrain, mesh p95 ≤ 4 ms and collision p95 ≤ 12 ms on A14/A13. Where a number below coincides with a physical target, it was derived independently from the simulator evidence and measures something different: scene-update callbacks rather than presented frames, and host CPU rather than device CPU.

**Validity rule.** If window I (idle control) of a run breaks the interval budgets, that run is void (host noise). Repeat it, at most twice. It is not counted as a candidate failure.

| Metric | Simulator budget | Window | Baseline observation it rests on |
|---|---|---|---|
| Scene-update interval p95 | **≤ 20.0 ms** | I, S | Spike 00 terrain p95 17.0 ms (iPhone 12 geometry) and 16.9 ms (iPad 9th generation geometry), 424 intervals each. All 8 accepted windows are ≤ 17.0 ms. The budget keeps p95 below the next 60 Hz step (33.3 ms), so fewer than 5% of intervals may be doubled. |
| Scene-update interval p99 | **≤ 25.0 ms** | I, S | Spike 00 terrain p99 21.0 / 18.1 ms. 5 of 6 SpriteKit windows were 16.7 ms. The iPhone blocks windows (29.0 / 28.3 ms) included mode entry and automated taps in 355-interval windows, so they are not sustained comparables; window I checks this per run. |
| Share of intervals > 33.3 ms (> 0.0333 s) | **≤ 0.5%** (at most 18 of about 3,600 in S) | I, S; B reported | Spike 00 terrain 1/424 = 0.24% on both geometries. The budget is about 2× that rate. |
| Worst interval | Reported. Any interval > 100 ms is flagged and inspected. | All | Spike 00 terrain worst 63.8 / 70.8 ms |
| Mesh CPU per command p95 (sum over dirty chunks: extraction plus `MeshResource`/LowLevelMesh update; main-actor part reported separately) | **≤ 4.0 ms** (2D: tile/texture update ≤ 4.0 ms) | S | Spike 00 `MeshDescriptor` rebuild of 625 vertices / 1,152 triangles: 1.30, 1.11, 1.39, 1.00 ms (4 samples, both geometries). Candidate A's dirty set (≤ 676 vertices) is that size. The budget is about 2.9× the largest sample, and ≤ 25% of one 16.7 ms interval. 2D has no texture-update baseline and rests on the interval-share argument only. |
| Collision regeneration per chunk job p95 (wall time including async wait) | **≤ 25 ms** | S | Spike 00 625-vertex `generateStaticMesh`: 15.12, 19.34, 14.93, 14.36 ms (4 samples). Budget is the largest sample (19.34) plus about 30%. Candidate A's chunk jobs (169 vertices) are smaller than the baseline workload. |
| Collision lag (command accepted → colliders for its whole dirty set installed, or superseded by a newer installed revision) | **p95 ≤ 100 ms, max ≤ 250 ms** (2D: visual lag p95 ≤ 33.4 ms) | S (B reported) | One command interval at 10/s. Per-job baseline 14–19 ms × up to 4 chunks leaves headroom. |
| Collision cadence policy | Per chunk: ≤ 1 job in flight plus 1 dirty flag; the latest rule state wins; at most one job per chunk per command. Install the dirty set of one revision together, so chunk seams never mix revisions. Input is never blocked while jobs are pending. On pause, finish and discard the jobs, then regenerate dirty chunks on resume; the rules are not rolled back. | All | Spike 00 finding: collision generation dominates and controls were disabled during regeneration. Rules are now authoritative, so the renderer catches up instead of gating input. |
| Correctness | Score 24 after S and 28 after B, 8 controls untouched; identical across render cadence and delay variants and both geometries. No accepted command is lost to coalescing (only mesh and collider work is coalesced). | S, B, cadence runs | Spike 11 test plan: deterministic rule state independent of mesh timing |
| Footprint growth over 5 restart cycles (`phys_footprint` snapshot after each cycle's settle) | **Cycle 5 − cycle 1 ≤ 8 MiB**, and not 4 consecutive deltas each > 1 MiB (leak signature). Absolute values recorded (flag > 133 MiB, 2× the baseline). | R | Spike 00 terrain snapshots 66.4 / 66.9 MiB. The largest lifecycle snapshot change was +6.6 MiB (iPhone, terrain 66.4 → resumed 73.0) and +1.6 MiB on iPad. These are snapshots, not peaks. |
| Entity and subscription count per restart | Equal to cycle 1 in every cycle | R | Spike 00 lifecycle lesson: cancel subscriptions on disappearance; no duplicate subscriptions (test plan) |
| Reload time (restart accepted → rule reset, all chunk meshes and colliders installed, collectibles placed, first subsequent scene update) | **≤ 500 ms in every cycle** | R | **No direct baseline exists**: Spike 00 reported initial construction but retained no reload sample. The budget is composed from baseline per-job observations: 16 chunks × ≤ 25 ms collision, about 400 ms serialized, plus 16 × ≈ 1.4 ms mesh. The first runs' values are recorded and not used to retune the budget. |

**Decision rule.** A candidate meets the budget only if both geometries pass every budgeted row in both runs. If no 3D candidate does, Epic 12 starts from candidate C (2D), as the brief states. Do not extend the spike.

---

## 5. Risks for the decision record

1. **Collision dominates and is unmeasured on devices.** The host baseline of 14–19 ms for 625 vertices already exceeds the 12 ms physical target. Mitigations: chunking, coalescing, rule-authoritative scoring and rule-space hit-testing.
2. **Simulator Metal and GPU behaviour is not representative.** Apple says so explicitly. GPU, thermal, battery and memory pressure remain unmeasured. Do not build a compute path.
3. **The host has drifted since Spike 00** (macOS 27.0 → 27.2, Xcode 27.0 → 27.1, chip unrecorded). The calibration run is required before any comparison.
4. **Voxel extraction cost.** Upstream numbers imply about 20–28 ms per command at 16³ chunks with a dictionary-based implementation, so an original array extractor is needed. The budget may still fail. That would be evidence for scope, not a reason to grow the engine.
5. **Chunk seams.** Normals are taken from the global grid. Colliders for a revision are installed together.
6. **Minimum runtime.** iOS 18.0 compiles locally but is not executed. The hosted CI iOS 18.0 job is the only route to runtime coverage at the floor.
7. **UI input faults (N06/N09/N10).** The measured run uses one tap plus the in-app driver. Retries are classified by the existing collector.
8. **The 2D top-down candidate loses object physics.** A side-view variant would need `SKPhysicsBody(texture:)` regeneration, which is unbudgeted and outside this workload.

## Sources

- https://developer.apple.com/documentation/realitykit/lowlevelmesh
- https://developer.apple.com/documentation/realitykit/meshdescriptor
- https://developer.apple.com/documentation/realitykit/meshresource
- https://developer.apple.com/documentation/realitykit/creating-a-plane-with-low-level-mesh
- https://developer.apple.com/documentation/realitykit/generating-interactive-geometry-with-realitykit
- https://developer.apple.com/documentation/realitykit/shaperesource/generatestaticmesh(positions:faceindices:)
- https://developer.apple.com/documentation/realitykit/shaperesource/generatestaticmesh(from:)
- https://developer.apple.com/documentation/realitykit/shaperesource/generateconvex(from:)-6upj9
- https://developer.apple.com/documentation/updates/realitykit
- https://developer.apple.com/documentation/metal/developing-metal-apps-that-run-in-simulator
- https://developer.apple.com/documentation/spritekit/skmutabletexture
- https://developer.apple.com/documentation/spritekit/skphysicsbody/init(texture:alphathreshold:size:)
- https://github.com/heckj/Voxels (commit bf3fe6767497c55d9a510b6172868a60798bba89)
- https://github.com/metal-by-example/metal-spatial-dynamic-mesh (commit 8b04589f51bae9b64d7f4356c14d5a544437c4a8)
- https://github.com/heckj/Heightmap, https://github.com/tayloraswift/swift-noise, https://github.com/pointfreeco/swift-issue-reporting (license metadata via `gh api`)
- SDK: `iPhoneSimulator27.1.sdk` RealityFoundation, _RealityKit_SwiftUI and SpriteKit headers (paths and lines above)
- Repo (worktree `edfd936`): `roadmap/audits/spike-00-platform-baseline.md`, `experiments/platform-baseline/{README.md,terrain-notes.md,evidence/*-final.txt,Sources/Diagnostics/*.swift,Sources/Terrain/*.swift}`, `roadmap/acceptance/spike-00-device-record.md`, `roadmap/decisions/ADR-002/003/006/007`, `roadmap/plans/later-spike-test-plans.md`, `ROADMAP.md`, `docs/privacy-contract.md`, `CONTRIBUTING.md`
