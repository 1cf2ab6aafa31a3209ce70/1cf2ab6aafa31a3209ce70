# ADR-001 — Start with a first-party Apple foundation

**Date:** 2026-09-30  
**Status:** Accepted for the starting direction of Spike 00. Platform support and renderer feasibility remain subject to that spike's measurements.  
**Owner:** Game-core maintainer; the Spike 00 implementer owns the hardware evidence.

## Context

The repository contains a roadmap and no game source. Its product contract requires offline operation, no analytics or accounts, original title identity, and a small shared core. Reusing a complete game would also import title rules, resources, persistence assumptions, and service integrations that this core does not need.

The [preflight audit](../audits/preflight-open-source-reuse.md) records exact revisions, build evidence, licenses, privacy boundaries, and the disposition of Donpa Squad, Leaves of Blocks, and GateEngine. Those findings inform this decision; a successful upstream build alone does not approve code or asset reuse.

## Decision

Start Spike 00 with an original SwiftUI shell, SpriteKit for the board/panel prototypes, and a separate RealityKit terrain experiment. Keep simulation and title rules independent of rendering and platform services. Prototype shared state interfaces in plain Swift; do not import a candidate game package or engine into the production repository.

Use Donpa as a reference for headlessly testable rules, a rendering adapter, and thin platform entry points. Its package also contains concrete cloud/keychain adapters, so the package boundary itself is not an offline guarantee. Use Leaves as a reference for board input geometry, accessibility labels and reduced-motion patterns, localization checks, and release checks. Playable non-drag board input still needs independent design and verification. Reimplement the needed concepts for this project's original rules. These decisions authorize design references, not copying code, translations, tests, artwork, sound, branding, or release configuration.

Decline GateEngine as the starting foundation. Its cross-platform engine and dependency surface have no demonstrated benefit for the current Apple-only scope. Do not retain it for the mandatory Spike 00 comparison: that comparison is conditional on preflight retaining it. Reconsider only if measured first-party limitations reveal a concrete requirement it can satisfy, with a new pinned dependency and asset review before inclusion.

Epic 01 will implement the existing `GameCore` / `GamePlatform` / title-module boundaries after Spike 00 establishes the OS/device matrix and renderer evidence. This ADR does not select minimum OS versions, certify terrain performance, or start production implementation.

## Alternatives and consequences

| Option | Benefit | Cost and disposition |
| --- | --- | --- |
| Adopt Donpa's package or fork its app | Existing rules/render separation and tests | Title-specific models and resources; cloud adapters inside the package and Game Center in the app. Use the architecture as a reference. |
| Extract a small Leaves component | Existing geometry and interaction examples | Requires isolation from title state, accessibility adaptation, original fixtures, and notices. Reference-only now; the candidate report estimates a future extraction. |
| Adopt GateEngine | One Swift abstraction across 2D, 3D, and multiple platforms | Additional engine APIs, bundled code/assets, package resolution, and upgrade work without measured need. Decline. |
| First-party frameworks with original core | Small dependency boundary and direct control over offline behavior | The team writes its own adapters, tests, and original game content. Chosen. |

The initial third-party inclusion bill of materials is empty. The project retains responsibility for save durability, lifecycle correctness, accessibility, and input behavior; these are not solved by studying upstream examples. Apple frameworks also require actual app-bundle and runtime privacy checks in Epic 08.

## Fallback and reversal

If RealityKit cannot support the intended terrain interaction on the oldest chosen hardware, keep the core and board titles on the first-party foundation and scope the dig title to a 2D excavation prototype. Spike 00 must record the failing device, OS, workload, frame pacing, and memory evidence. Spike 11 can revisit terrain technology once the mechanic and budget are defined.

If SpriteKit or the SwiftUI host fails the board/input requirements, record a failing minimal sample and compare a focused first-party rendering or hosting alternative before widening the dependency surface. Do not compensate by coupling engine types to core rules. A later GateEngine evaluation must reproduce the same workload, disclose its full resolved dependency graph and notices, and demonstrate a benefit on the acceptance hardware.

Reversal currently costs documentation changes and disposable prototype work because no external code is included. After Epic 01, maintaining renderer-independent core types limits replacement primarily to platform adapters and title scenes. The maintainer records any change of foundation in a superseding ADR.

## Spike 00 handoff

Proceed with its existing board/panel, lifecycle/input, and terrain experiments. Record exact toolchain, minimum OS versions, devices, reproducible build commands, and measurements. Preflight build results are evidence about upstream revisions on the audit host, not acceptance measurements for this project's titles.
