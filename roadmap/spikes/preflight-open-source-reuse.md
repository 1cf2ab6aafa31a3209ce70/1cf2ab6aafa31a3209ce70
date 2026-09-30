# Preflight spike — Open-source reuse audit

**Decision needed:** Which existing repositories can shorten the native, offline multi-title build without importing analytics, network features, incompatible assets, or an oversized engine?

**Timebox:** Two developer days. **Entry:** Roadmap approved; no game code exists. **Next:** Spike 00 platform and rendering baseline. This is the first ordered work item.

## Candidates and intended fit

| Repository | Examine for | Later work informed |
| --- | --- | --- |
| [Donpa Squad](https://github.com/vlumi/donpa) | Pure rules package, SpriteKit/SwiftUI boundary, thin iOS/macOS targets, saves, tests | Epics 01, 02, 04, 07 |
| [Leaves of Blocks](https://github.com/timveil/leaves-of-blocks) | Block interaction, accessibility, localization, CI/release scripts | Epics 08–09 |
| [GateEngine](https://github.com/STREGAsGate/GateEngine) | A unified Swift engine for 2D/3D and its dependency/maintenance cost | Spike 00 |

Terrain-specific [Voxels](https://github.com/heckj/Voxels) and the [RealityKit dynamic-mesh example](https://github.com/metal-by-example/metal-spatial-dynamic-mesh) wait for Spike 11, when the dig mechanic and target device budget are defined.

## Investigation

1. Pin the exact commit or release reviewed for each candidate. Build its relevant sample with the team's current Xcode toolchain, or record the concrete build blocker.
2. Inventory code and asset licenses, notices, transitive dependencies, required OS versions, maintenance signals, and any restrictions on names, artwork, or redistribution.
3. Trace runtime data flows and app capabilities: network calls, local analytics/history, Game Center, iCloud, sign-in, ads, purchases, and permissions. Distinguish removable title features from dependencies embedded in reusable code.
4. For Donpa and Leaves, identify one small vertical slice that could be reused or adapted for the planned core. Estimate the extraction and test cost. For GateEngine, compare a minimal board scene and terrain placeholder against first-party framework prototypes in Spike 00.
5. Record one decision per candidate: adopt as a pinned dependency, extract a narrow licensed component, use as a pattern/reference, or decline. State the expected maintenance owner and reversal cost.

## Exit evidence

- A candidate matrix with pinned revisions, build result, license and asset findings, runtime privacy findings, applicable roadmap epic, and decision rationale.
- A dependency bill of materials for anything proposed for inclusion, including transitive packages and required notices.
- A short architecture decision record choosing the starting foundation for Spike 00 and Epic 01, with a fallback if the preferred candidate fails on target hardware.

No external source or assets enter the game repository until the license and privacy review passes. A repository can still be useful as a documented design reference when its runtime features do not meet the product rules.
