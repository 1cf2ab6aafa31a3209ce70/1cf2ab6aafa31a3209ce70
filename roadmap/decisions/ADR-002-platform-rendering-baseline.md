# ADR-002 — Platform and rendering baseline

**Date:** 2026-09-30  
**Status:** Historical provisional decision. [ADR-003](ADR-003-simulator-mobile-foundation.md) supersedes its physical-device and macOS completion gates on 2026-10-01 and accepts the mobile foundation using simulator evidence. The observations and original budget proposals below are retained as recorded.
**Owner:** Platform/rendering maintainer.

## Context

[ADR-001](ADR-001-first-party-foundation.md) chose original first-party prototypes after the reuse audit. The next decision must establish supported platforms without making terrain technology a dependency of shared game rules. The user selected iPhone 12 and iPad (9th generation) as acceptance hardware and deferred the macOS release until after mobile.

The [disposable experiment](../../experiments/platform-baseline/README.md) now separates Foundation-only board geometry and heightfield simulation from SpriteKit and RealityKit rendering. [The evidence report](../audits/spike-00-platform-baseline.md) distinguishes observed build/interaction results from physical performance still requiring validation.

## Starting platform matrix

| Platform | Proposed floor | Acceptance device | Release intent and remaining evidence |
| --- | --- | --- | --- |
| iOS | 18.0 | iPhone 12 | First release; verify minimum-OS behavior, sustained display pacing, peak memory, touch and lifecycle on hardware |
| iPadOS | 18.0 | iPad (9th generation) | First release; verify rotation/resize, safe areas, touch, pointer and hardware keyboard on hardware |
| macOS | 15.0 | Current arm64 development Mac | Development/portability target; shipping deferred, release hardware/floor may be revisited |

The non-AR `RealityView` API used by this experiment establishes the proposed iOS 18/macOS 15 floor. The installed Xcode SDK's availability declarations and successful target compilation support API feasibility, not a runtime pass on the minimum OS. Xcode 27.0/Swift 6.4 are the observed development toolchain; the sample compiles in Swift 5 language mode. Pinning a supported contributor toolchain belongs to Epic 01 after the baseline is accepted.

## Renderer and responsibility decision

Continue with SwiftUI for controls and SpriteKit for 2D board/panel rendering. Use `SpriteView` with explicit native view/scene pause synchronization when lifecycle changes, and stable scene ownership. Keep input translation and viewport layout distinct from game rules. The unscrew scene is an input/rendering placeholder, not evidence for completed panel physics.

Retain RealityKit as a provisional 3D adapter for further terrain work. This experiment regenerates a small heightfield mesh with `MeshDescriptor`, builds a static collision shape separately, and drops a dynamic sphere to probe the updated surface. Simulation owns radial excavation/topology; the adapter owns mesh resources, collision generation, camera, hit conversion and entity lifecycle. A 625-vertex surface does not establish feasibility for caves, voxel chunks, overhangs, or Epic 12's final dig mechanic.

Do not introduce Metal compute, custom rendering, or GateEngine at this point. No measured requirement yet justifies that cost. The GateEngine disposition from preflight remains decline; any renewed comparison needs an explicit unmet requirement, pinned graph, resource clearance, and the same acceptance workload.

Shared core types must remain independent of SpriteKit/RealityKit entity, scene and mesh types. The experiment's Foundation-only package is disposable and does not establish production `GameCore`, save or module contracts.

## Acceptance targets and fallback

Use the [physical procedure](../../experiments/platform-baseline/README.md#physical-acceptance-procedure) to test 60 Hz interaction, sustained presented-frame p95 ≤20 ms/p99 ≤33.4 ms, and peak footprint ≤150 MiB for board/panel and ≤250 MiB for this tiny terrain workload. Proposed p95 terrain CPU budgets are ≤4 ms for mesh generation and ≤12 ms for collision regeneration. These are initial targets to validate, not results inferred from simulator update timestamps.

If first-party terrain misses the budget on either selected device, record the actual workload/failure before changing technology. Reduce or decouple collision update work only if input/collision correctness remains observable. Spike 11 may then compare a focused low-level mesh/compute implementation; if the desired mechanic still cannot fit, choose the existing 2D excavation fallback. Keep the accepted board/core foundation independent of that later choice.

If SpriteView's hosting or input fails on acceptance hardware, retain SpriteKit and compare a small native SKView wrapper using a failing reproduction. The prototype already found that explicit lifecycle synchronization is necessary on the tested simulator; this is not evidence that an entire engine must replace SpriteKit.

## Consequences and remaining gates

The small dependency boundary and original generated content simplify licensing and capability review. The team still owns accessible gameplay, actual display timing, memory pressure, interruption handling and renderer-adapter tests. Diagnostic counters in this disposable sample stay in memory and do not become production analytics.

Full macOS UI validation remains open: an ad hoc signed partial run observed pointer/keyboard and terrain rest, while later retries had inconsistent window/input delivery. macOS shipping is deferred. Final mobile integration bundles were finalized and both simulator landscape captures were visually inspected; physical layout/performance acceptance remains open.

Before closing Spike 00, record physical Release runs on both selected devices, minimum-OS behavior, sustained frame/memory measurements, input/collision observations, and an explicit terrain scope decision from that evidence. Full-device offline/permission checks and accessibility checks also remain open. Epic 01 implementation remains gated by the roadmap; documentation preparation can proceed independently. This ADR becomes accepted only when those gates have evidence or the spike records a deliberate scope fallback.
