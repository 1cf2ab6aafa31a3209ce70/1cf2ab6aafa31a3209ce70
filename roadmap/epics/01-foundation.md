# Epic 01 — Repository and privacy foundation

**Outcome:** A new contributor can clone and build a native mobile monorepo with shared packages and separate title targets. The repository establishes offline, no-telemetry rules before gameplay code appears.

**Entry:** Preflight and Spike 00 are complete; their reuse, platform, and renderer decisions are recorded. **Next:** Epic 02. This epic depends on all earlier ordered work.

## Implementation — 2026-10-01

**Status:** Implementation and local build/UI checks complete; configured hosted CI acceptance pending. Epic 02 has not begun. [The evidence report](../audits/epic-01-mobile-foundation.md) records two passing simulator smoke runs, Debug/Release builds, package boundary checks and an independent clean filesystem-copy build. This does not claim a clean committed checkout or remote workflow pass. [ADR-003](../decisions/ADR-003-simulator-mobile-foundation.md) accepts Spike 00 using retained mobile simulator evidence and satisfies this epic's entry gate. The user selected MIT for project-authored code, documentation and resources, confirmed no physical device is available, and deferred macOS work. Minimum-runtime execution remains a distribution-readiness check rather than a foundation block.

The [contribution guide](../../CONTRIBUTING.md), [privacy contract](../../docs/privacy-contract.md), and [content provenance policy](../../docs/asset-provenance.md) define the implementation baseline. This epic builds original packages, a thin mobile development title and reproducible mobile checks; it does not import the disposable experiment's terrain or diagnostic HUD into production.

## Scope and tasks

1. Initialize Git, an Xcode workspace, a shared Swift package (`GameCore`), a development title target, and a pure-logic test target. Pin the selected Swift/Xcode and minimum OS versions in contributor docs.
2. Define package boundaries: `GameCore` for flow/state/content interfaces; `GamePlatform` for Apple audio, haptics, storage, and rendering adapters; `Games/<Title>` for each game's rules, scene, assets, and levels. Avoid a renderer dependency in core model types.
3. Apply MIT to project-authored code, documentation and resources, preserve future third-party rights/notices, and document the asset-provenance policy; add `CONTRIBUTING.md`, architectural decision records, and an original-content provenance template.
4. Add build/test scripts and CI for the supported iOS/iPadOS simulator targets. macOS is deferred. Validate that a clean checkout builds without secrets or external runtime services.
5. Document the app privacy contract and add a dependency/entitlement/Info.plist review checklist. Prevent accidental inclusion of tracking, ads, payments, network client SDKs, and data collection.
6. Use preflight-approved architecture patterns as references; no upstream code, tests, assets or tooling is approved for copying. Any future inclusion requires a separate review with required notices and pinned revisions; keep excluded features and assets out of the build.

## Acceptance

- Clean checkout builds the empty title and core test target on the configured mobile CI environment; structural checks validate package dependency boundaries. The empty core has no domain behavior yet, so runtime core cases begin with the first domain API rather than inventing one for this skeleton. Record local results separately from a configured remote workflow.
- Title target can import the shared package; shared package cannot import a title.
- A contributor can identify supported platforms, build commands, licenses, privacy rules, and where a new title belongs from the repository docs.
- No runtime network request, tracking permission, monetization, or telemetry dependency is present.

**Outside this epic:** Gameplay systems, full menus, persistence, and release submission.
