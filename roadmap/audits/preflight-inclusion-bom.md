# Preflight inclusion bill of materials

**Audit date:** 2026-09-30  
**Scope:** Material proposed for inclusion in this repository or its future app targets by the [preflight decision](../decisions/ADR-001-first-party-foundation.md).

## Inclusion inventory

| Material | Included or approved for copying | Direct third-party dependencies | Transitive third-party dependencies | Notices to distribute |
| --- | --- | --- | --- | --- |
| Donpa Squad source, tests, resources, tooling | None; design reference only | None | None | None introduced by this audit |
| Leaves of Blocks source, tests, resources, tooling | None; design reference only | None | None | None introduced by this audit |
| GateEngine source, packages, resources, tooling | None; declined | None | None | None introduced by this audit |

This is an empty inclusion inventory, not a claim that the candidates have no dependencies or license obligations. Temporary upstream checkouts and build products used for investigation are outside the game repository. Only authored audit documentation is added here. No Swift package, lockfile, copied test, binary, image, sound, font, or third-party release tool is proposed for inclusion.

Apple's Swift standard library and the proposed SwiftUI, SpriteKit, RealityKit, and Foundation frameworks are platform/toolchain inputs, not newly vendored open-source packages. The audit host used Xcode 27.0 (27A266a), Swift 6.4 (swiftlang-6.4.0.34.1), and Apple SDKs 27.0. Spike 00 must pin the supported development and deployment matrix; these observed versions do not establish it.

## Candidate inventories and future notice requirements

| Candidate | Upstream inventory | Condition before any later copying or dependency adoption |
| --- | --- | --- |
| Donpa | [Pinned package, services, code license, and reserved assets](preflight-donpa.md) | Review the exact slice and its imports/resources; retain the MIT copyright and permission notice for copied substantial code, including tests. Exclude reserved title identity and art. Remove cloud/keychain/service coupling from the selected boundary and verify its replacement. |
| Leaves | [Runtime frameworks, development tooling, MIT license, and assets](preflight-leaves.md) | Isolate the slice from analytics/history and Game Center; retain the MIT copyright and permission notice for copied substantial code, including tests/tooling. Review any resource separately; a code license alone does not settle provenance. |
| GateEngine | [Resolved packages, bundled modules, licenses, and platform conditions](preflight-gateengine.md) | Reopen the adoption decision, pin the entire resolved graph, inventory active bundled code and assets for each target/configuration, and assemble the applicable MIT/BSD/Apache and other notices. The current candidate inventory is not approval to redistribute an engine build. |

References to source are evidence links, not permission to vendor it. Any later inclusion needs a new row recording upstream URL, full revision, exact copied paths or package product, local destination, license and notice location, transitive graph, asset provenance, runtime data flows, supported platforms, review result, and maintenance owner. Record bundled C/C++ code and fonts as well as package-manager dependencies.

The game-core maintainer owns this inventory. Update it in the same change that first introduces third-party material; do not treat this audit's empty inventory as permanent license or privacy clearance.
