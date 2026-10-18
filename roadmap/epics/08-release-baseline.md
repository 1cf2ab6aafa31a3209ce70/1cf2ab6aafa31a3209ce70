# Epic 08 — Quality and release baseline

**Outcome:** Any title built on the core has a repeatable path to a reviewable offline release candidate. Automated gates run in CI for every app target; a per-title checklist covers what automation cannot.

**Entry:** Epic 07 has two app targets and a version 1 module contract, and Spike 11 has confirmed or amended that contract. **Next:** Epic 09A. This epic depends on all earlier ordered work.

**Execution policy:** Follow [ADR-003](../decisions/ADR-003-simulator-mobile-foundation.md). Physical devices are unavailable and macOS is deferred. Gates use simulators, inspection of built bundles and automated tests. Hardware-only behavior is a named pre-distribution check, not an exit criterion for this epic.

## Scope and tasks

1. Automate release gates in CI for every app target: audit built bundles, entitlements, Info.plist entries, linked frameworks and privacy manifests; detect URL sessions, web views, ad/IAP/analytics packages and tracking-permission APIs; validate localization and asset provenance; and check that the build reproduces from the documented instructions. Extend `scripts/check-foundation.py` where it already covers part of this.
2. Add a minimum-runtime job that runs app-hosted and UI tests on an iOS 18 simulator runtime, the deployment floor.
3. Record simulator observations for startup, scene-update intervals, process memory and package size on both geometries as regression baselines. Do not present them as physical budgets.
4. Build an accessibility checklist and apply it to the reference title: VoiceOver labels and focus, large text in menus, color-independent cues, reduced motion, audio/haptic controls, and a usable alternate input path for gameplay.
5. Write the per-title release checklist: offline and network-observation checks for exercised flows, App Store privacy answers verified against actual behavior (including required-reason API disclosures), a release notes template, the local reset/export path in the privacy description, and the pre-distribution hardware check.
6. Define that hardware check: startup, frame pacing, memory, thermal behavior and touch on at least one physical iPhone and one iPad of the supported generations. Where hardware is still unavailable, record an explicit release scope decision listing what remains unmeasured, as ADR-003 requires.

## Acceptance

- CI runs the automated gates on every app target, and each gate fails on a seeded violation.
- The reference title passes the automated gates, the minimum-runtime job and the accessibility checklist on both simulator geometries.
- App-bundle audit finds no ad, analytics, attribution, IAP, account, cloud, or push integration and no app-originated network traffic during exercised flows.
- A reviewer can trace every packaged third-party asset to its license and attribution requirement.
- Accessibility findings have either a fix or an explicit, tracked title-specific action before that title ships.

**Outside this epic:** Store submission, physical-device measurement (a pre-distribution check), external services, and title-specific content polish.
