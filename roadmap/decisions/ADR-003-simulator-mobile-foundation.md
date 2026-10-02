# ADR-003 — Simulator acceptance for the mobile foundation

**Date:** 2026-10-01
**Status:** Accepted; supersedes ADR-002's physical-device and macOS completion gates for Spike 00.
**Owner:** Game-core maintainer.

## Context

The user confirmed that no physical device is available for this work, selected the MIT license, and directed development to focus on mobile using common guidelines and best practices. Requiring physical iPhone 12 and iPad (9th generation) runs would prevent foundation work indefinitely. macOS is outside the current implementation and validation scope.

The [September 30 evidence](../audits/spike-00-platform-baseline.md) already records successful Debug/Release simulator builds, eight pure tests, and the final interaction suite on iOS 26 simulators matching both selected screen geometries. The suite checks board/panel touch, terrain rebuilding and sustained sphere rest on the excavated surface, portrait/landscape containment, pause and foreground restoration. Those observations support a mobile foundation decision; they do not certify real-device performance or a complete title.

## Decision

Accept Spike 00 for foundation development using its retained simulator evidence. Proceed with Epic 01's original mobile skeleton. Keep SwiftUI controls and SpriteKit 2D adapters; retain RealityKit as the starting terrain experiment, separate from renderer-independent core types. A 625-vertex heightfield is a feasibility sample, not the final dig mechanic. Metal, GateEngine and imported candidate code remain unapproved; Spike 11 will decide the full terrain scope with a defined workload.

| Item | Current decision |
| --- | --- |
| Supported production platforms | iOS and iPadOS; macOS is deferred and is not a current gate |
| Deployment floor | iOS/iPadOS 18.0 |
| Contributor/CI toolchain | Configured Xcode 26.6 (`17F113`) on `macos-26`; Swift 5 language mode |
| Observed local toolchain | Xcode 27.0 (`27A266a`), Swift 6.4 compiler; local simulator runtime 26.0 |
| Development acceptance | iOS 26.0 simulators with iPhone 12 and iPad (9th generation) geometry |
| Source and project-authored resources | MIT; preserve third-party rights and required notices for any future inclusion |

The configured CI runtime is iOS 26.5; the September 30 evidence uses local iOS 26.0. CI configuration is not itself a remote execution result.

Use pure automated tests for model behavior and invariants, unsigned Debug/Release simulator builds for integration, and simulator UI tests for observable interaction/lifecycle/layout. Record the simulator runtime, screen geometry, source revision and evidence for each run. Keep simulator results explicitly labeled.

The existing experiment is disposable. Production targets do not inherit its diagnostic HUD, terrain code or macOS target automatically. Epic 01 owns the package, title target, build/test automation, contributor instructions and privacy baseline; Epic 02 owns the playable lifecycle shell. Later rows retain their recorded dependencies, while independent planning can continue in parallel.

## Limits and release checks

Simulators do not establish physical CPU/GPU performance, presented-frame pacing, thermal behavior, battery use or device memory-pressure response. Scene-update intervals are not displayed-frame measurements, and footprint snapshots are not peak-memory evidence. The earlier physical performance budgets remain future workload targets; they are not passed or silently replaced with simulator thresholds.

An iOS 18 runtime is not installed. Availability checking and successful compilation with an 18.0 deployment target establish a build boundary, not runtime coverage of the floor. Minimum-runtime execution is a distribution-readiness check when a compatible simulator runtime or another test environment is available; its absence does not block foundation implementation.

Before distribution, review minimum-OS behavior, accessibility, offline/permission behavior, the actual built bundle and privacy declarations, signing and store metadata, and sustained representative workloads. Use simulator profiling and automated correctness checks where possible. Where hardware-only behavior remains unmeasured, record that limitation explicitly and make the release scope decision then. No physical-device result is required to continue the current development work, and no Mac work is required for the mobile foundation.

## Consequences and fallback

[Spike 00](../spikes/00-platform-baseline.md) is complete for the foundation decision under this revised acceptance scope. [Epic 01](../epics/01-foundation.md) can proceed; its own build/test acceptance still must pass. [The acceptance record](../acceptance/spike-00-device-record.md) preserves the boundary between simulator observations and unavailable physical evidence.

If a simulator interaction fails, retain the reproduction and repair the owning adapter or narrow its scope before advancing dependent behavior. If later terrain work cannot support the chosen mechanic, keep the mobile board/core foundation and use the existing 2D excavation fallback. Any future physical observations can inform a new renderer or release decision without changing the historical simulator results.
