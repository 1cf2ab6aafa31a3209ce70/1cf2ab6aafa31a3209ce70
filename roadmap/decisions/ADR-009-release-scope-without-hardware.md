# ADR-009 — Release scope without hardware

**Date:** 2026-10-20. **Status:** Accepted for Epic 08. It applies to every title until a recorded [hardware check](../../docs/hardware-check.md) passes on both device roles, or a later record replaces it.

## Context

[ADR-003](ADR-003-simulator-mobile-foundation.md) accepts simulator evidence for development and states that, where hardware-only behavior remains unmeasured before distribution, the limitation is recorded and a release scope decision made then. [Epic 08](../epics/08-release-baseline.md) asks for that decision now, alongside the hardware check it defines, because no physical iPhone or iPad is available and none is expected before the first titles reach the release checklist.

Epic 08's gates run on iOS simulators with iPhone 12 and iPad (9th generation) geometry, on the configured iOS 26.5 runtime in CI, the iOS 18.0 minimum runtime in the hosted minimum-runtime job, and iOS 26.0 locally. They inspect built bundles, run app-hosted and UI tests, run system accessibility audits and record simulator observations. None of them runs on a device.

## Decision

**A title may reach a reviewed offline release candidate on simulator evidence alone. It may not be distributed beyond the developer while the hardware check has not passed.** A release candidate is a Release build of a tagged revision that passes every automated gate and every simulator and manual step of the [release checklist](../../docs/release-checklist.md) and the [accessibility checklist](../../docs/accessibility-checklist.md). Distribution means external TestFlight, App Store submission, or any other copy given to people outside the project's development.

The release checklist's hardware item is marked **not run, ADR-009** for every candidate built under this decision. The candidate's release notes list the unmeasured items below. Store submission is outside Epic 08, so this decision blocks nothing Epic 08 or Epic 09A needs to finish: Epic 09A takes its title "through the release checklist" to a candidate, with the hardware item recorded as not run.

### What remains unmeasured

Simulator results do not establish, and no Epic 08 gate measures, any of the following:

| Area | Unmeasured | Nearest simulator evidence and its limit |
| --- | --- | --- |
| Startup | Cold and warm launch time on A13 and A14 hardware; launch under storage or memory pressure | None recorded as a budget; simulator launch times depend on the host Mac |
| Frame pacing | Presented-frame intervals and hitches; ADR-002's p95 ≤ 20 ms and p99 ≤ 33.4 ms targets | Scene-update callback intervals, which are not presented frames |
| Memory | Peak footprint against ADR-002's 150 MiB and 250 MiB targets; jetsam limits; response to a real memory warning | `phys_footprint` snapshots on the simulator, which run with the host's memory |
| Thermal and battery | Thermal state, throttling and battery drain over sustained play | None; the simulator has no thermal or battery model |
| GPU | SpriteKit and RealityKit rendering cost on device GPUs | Apple states that Simulator GPU behavior does not represent devices |
| Touch | Digitizer accuracy, latency, edge cells, multi-touch and palm contact on real glass | XCTest synthesized gestures, which also carry the simulator input faults N06 and N09 |
| Accessibility output | VoiceOver speech and gestures, Voice Control, Switch Control | System accessibility audits and accessibility-element tests; the iOS Simulator does not run VoiceOver |
| Audio and haptics | Haptic output; audio through the speaker, headphones and Bluetooth; the ring/silent switch; real route changes | Shell feedback tests with fake outputs; the simulator produces no haptics |
| Minimum OS on device | iOS and iPadOS 18.0 on hardware | The hosted iOS 18.0 simulator job |
| Distribution | Signing, provisioning, App Store processing and installation from TestFlight | Unsigned Release builds and bundle inspection |
| Files export | Export to a third-party file provider on device | Export to the simulator's local Files destination |

### When this decision ends

A title leaves this decision when its hardware check passes on one iPhone and one iPad as [defined](../../docs/hardware-check.md), with the result in its audit. A failed hardware step blocks distribution until it is fixed. A later decision record may narrow a release instead, for example to one device family. A partial check, such as an iPhone without an iPad, removes only the rows it measured, and the rest stay listed in the release notes.

## Alternatives

- **Distribute on simulator evidence, listing the unmeasured items in the release notes.** Rejected. ADR-002's frame and memory targets would ship unchecked, and no one would have heard VoiceOver speak the title. Players cannot weigh those gaps from a release note, and for this project the risk falls on accessibility users first.
- **Treat a faster device, or a Mac running the iPad app, as a substitute.** Rejected. It cannot show A13 or A14 frame pacing, memory or thermal behavior, and macOS is deferred. A faster device may add evidence; it does not replace a reference device.
- **Hold Epic 08 open until hardware is available.** Rejected. ADR-003 makes hardware a pre-distribution check, not an exit criterion, and the epic's other outcomes do not depend on it.

## Consequences

Epic 08 closes on simulator evidence. Epic 09A and later titles can finish their epics and produce release candidates. No title is distributed until hardware is available. When it is, the first hardware check also tests ADR-002's budgets for the first time. A miss there goes back to the owning title, or to ADR-002's fallbacks, with a new decision record. The simulator results stay as they are.
