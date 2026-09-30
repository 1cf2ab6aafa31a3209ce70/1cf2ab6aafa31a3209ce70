# Epic 01 — Repository and privacy foundation

**Outcome:** A new contributor can clone and build a native Apple monorepo with shared packages and separate title targets. The repository establishes offline, no-telemetry rules before gameplay code appears.

**Entry:** Preflight and Spike 00 are complete; their reuse, platform, and renderer decisions are recorded. **Next:** Epic 02. This epic depends on all earlier ordered work.

## Scope and tasks

1. Initialize Git, an Xcode workspace, a shared Swift package (`GameCore`), a development title target, and a pure-logic test target. Pin the selected Swift/Xcode and minimum OS versions in contributor docs.
2. Define package boundaries: `GameCore` for flow/state/content interfaces; `GamePlatform` for Apple audio, haptics, storage, and rendering adapters; `Games/<Title>` for each game's rules, scene, assets, and levels. Avoid a renderer dependency in core model types.
3. Add a license suitable for code and a separate asset-license policy; add `CONTRIBUTING.md`, architectural decision records, and an original-content provenance template.
4. Add build/test scripts and CI for every supported target. Validate that a clean checkout builds without secrets or external runtime services.
5. Document the app privacy contract and add a dependency/entitlement/Info.plist review checklist. Prevent accidental inclusion of tracking, ads, payments, network client SDKs, and data collection.
6. Apply preflight-approved code or architecture patterns with required license notices and pinned revisions; keep excluded features and assets out of the build.

## Acceptance

- Clean checkout builds the empty title and runs core tests on the chosen CI environment.
- Title target can import the shared package; shared package cannot import a title.
- A contributor can identify supported platforms, build commands, licenses, privacy rules, and where a new title belongs from the repository docs.
- No runtime network request, tracking permission, monetization, or telemetry dependency is present.

**Outside this epic:** Gameplay systems, full menus, persistence, and release submission.
