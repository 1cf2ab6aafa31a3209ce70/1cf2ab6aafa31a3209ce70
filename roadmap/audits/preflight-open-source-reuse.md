# Preflight results — Open-source reuse

**Reviewed:** 2026-09-30  
**Scope:** The three candidates in the [preflight brief](../spikes/preflight-open-source-reuse.md).  
**Decision:** Use Donpa and Leaves as design references; decline GateEngine as the starting foundation. Include no external code or assets. Start Spike 00 with original SwiftUI/SpriteKit prototypes and a separate RealityKit terrain experiment, as recorded in [ADR-001](../decisions/ADR-001-first-party-foundation.md).

## Candidate matrix

Full hashes identify the reviewed source, not a promise to track future upstream HEAD. Each candidate report contains immutable file links, exact commands, retained result excerpts, dependency and capability findings, extraction estimates, ownership, and limitations.

| Candidate and pinned revision | Build result on audit host | License and assets | Runtime privacy findings | Roadmap fit and decision |
| --- | --- | --- | --- | --- |
| [Donpa report](preflight-donpa.md) — [`162955f33769e30d3a2d19cece13e2abac001519`](https://github.com/vlumi/donpa/commit/162955f33769e30d3a2d19cece13e2abac001519) | Package builds/tests pass: 564 core tests and 119 renderer tests reported, including 3 skips, zero failures. App generation blocked by missing XcodeGen; iOS/macOS apps not built. | MIT code; names, icons, manga/title art and visual branding expressly reserved. Other media not cleared. No external SwiftPM packages. | Concrete iCloud adapters and synchronizable keychain identity exist inside the core; Game Center preference sync is separate from the score-sync switch. App adds Game Center, nearby sharing, camera and network capabilities. | **Reference only**, Epics 01/02/04/07 and Spike 03. Learn from rules/render separation, platform wrappers and save tests; write original, title-neutral interfaces. A formatter extraction is possible but has no clear cost advantage over writing it. |
| [Leaves report](preflight-leaves.md) — [`151ec8334423dd5023f1e27e9cb17e1f840a2193`](https://github.com/timveil/leaves-of-blocks/commit/151ec8334423dd5023f1e27e9cb17e1f840a2193) | Debug simulator app/unit/UI bundles build; 429 unit tests in 117 suites pass on iOS 26.0 iPhone 17 Pro simulator. UI tests not run. | MIT project license; individual asset provenance unresolved. No third-party app packages; release gems/CI dependencies excluded. | Local gameplay analytics and Core Data history are integrated into state/service paths. Optional Game Center authenticates and submits data; external links carry attribution parameters. | **Reference only**, Epics 08/09. Study drag geometry, locale validation and CI separation. Do not inherit full state/history, resources, manifest or release tooling. Accessible non-drag placement still needs original work. |
| [GateEngine report](preflight-gateengine.md) — [`8ac4b58b5465c165f408b240b92c67a1948797da`](https://github.com/STREGAsGate/GateEngine/commit/8ac4b58b5465c165f408b240b92c67a1948797da) | Debug library builds; an original minimal macOS window executable compiles and links with Swift 6.4. No window launch or board/terrain runtime test. | Apache-2.0 engine plus remote packages, bundled third-party code and resources with separate obligations; asset clearance incomplete. | Native paths inspected are local; web backend has fetch behavior. No runtime traffic capture or blanket privacy clearance. | **Decline**, Spike 00. Engine/dependency/resource scope has no demonstrated benefit for this Apple-only core. Not retained for a required comparison; reconsider only for a measured unmet requirement. |

## Environment and interpretation

The audit host is arm64 macOS 27.0 (`26A428`), using `/Applications/Xcode.app/Contents/Developer`, Xcode 27.0 (`27A266a`) and Apple Swift 6.4 (`swiftlang-6.4.0.34.1`). Xcode lists Apple SDKs 27.0. Leaves unit tests used an already installed iOS 26.0 simulator runtime. These are observed audit inputs, not GameCore's minimum OS or supported toolchain decision.

Public source was downloaded into `/private/tmp/gamecore-reuse-audit/`, outside this repository. Build manifests and relevant scripts were reviewed before execution. Sandbox access failures were distinguished from upstream build failures; permitted retries are described in the reports. No release/upload workflow ran. Donpa's missing generator is a concrete app-build blocker allowed by the brief, not a successful app build or a reason to infer source incompatibility.

The review combines source-level data-flow tracing, manifests/entitlements/resources, and the specified build/tests. It does not certify any candidate app as network-free: no packet capture, complete interactive privacy exercise, physical-device performance run, or store archive validation was performed. A negative direct-HTTP search does not exclude service traffic from Apple frameworks. Reference-only decisions do not depend on such certification because no upstream executable material is being included.

## Reuse and ownership

| Candidate | Smallest practical use and estimated effort | Local owner | Reversal cost |
| --- | --- | --- | --- |
| Donpa | Time-format/display slice: 0.5–1 developer day including tests for either narrow extraction or original implementation. Original snapshot/save/lifecycle sample informed by its architecture: 1.5–3 days; full durability remains Spike 03/Epic 04 work. | Shared-core maintainer; platform maintainer reviews capabilities | No runtime cost now. Later save-format changes require migrations; do not assume they are cheap. |
| Leaves | Drag → valid-cell preview → placement slice: 2–3 days after the module seam exists; another 1–2 days for accessible non-drag placement. Geometry alone: about 1 day including tests. | Epic 09 title maintainer; Epic 08 quality maintainer | No runtime cost now; an isolated future geometry extraction could be replaced in about 0.5–1 day. |
| GateEngine | No extraction or adoption proposed. A future comparison needs an actual hardware requirement and the same board/terrain workload as the first-party baseline. | Spike 00 renderer maintainer | No runtime cost now; adopting engine APIs across scenes later would increase replacement cost. |

Estimates are planning ranges for the defined slices, not observed implementation time. Owners are project roles pending named assignment. Maintenance observations are revision-specific and do not imply upstream support commitments or green hosted CI.

## Inclusion and exit evidence

The [inclusion bill of materials](preflight-inclusion-bom.md) records **zero third-party source, assets, packages or tooling proposed for inclusion**, so this audit introduces no redistribution notices. Candidate reports inventory excluded dependencies and describe notice/provenance work required before any later copying. Referencing a pattern is not license or privacy clearance for its implementation.

| Brief requirement | Evidence and disposition |
| --- | --- |
| Exact revisions and relevant builds or concrete blockers | Matrix and candidate reports; Donpa app builds remain blocked by missing XcodeGen |
| Code/assets, dependencies, OS floors and maintenance | Candidate inventories; unsupported or unclear asset rights remain excluded |
| Runtime flows and removable versus embedded features | Source traces in all three reports; local analytics and cloud initialization explicitly considered |
| Reusable slices and costs | Donpa and Leaves reports and table above; GateEngine declined before a hardware comparison |
| One disposition, owner and reversal cost per candidate | Matrix, ownership table and candidate reports |
| Inclusion BOM and notices | Empty inclusion BOM with explicit future review requirements |
| Starting foundation and hardware fallback | ADR-001; first-party prototypes, renderer-independent rules, and a 2D dig fallback if terrain fails on acceptance hardware |

**Preflight is complete as a bounded reuse decision.** Proceed to [Spike 00](../spikes/00-platform-baseline.md); it still owns platform selection, representative rendering prototypes and hardware measurements. The two-day budget in the brief is a ceiling, not a claim of elapsed effort. No production code has been started. Voxels and the dynamic-mesh example remain deferred to Spike 11.
