# App privacy contract

This contract derives from the [roadmap](../ROADMAP.md) and applies to the [mobile foundation](../roadmap/epics/01-foundation.md), [shared shell](../roadmap/epics/02-app-shell.md) and later titles. It states required behavior, not a runtime certification. The disposable experiment has build, simulator-test and source-scan evidence in the [Spike 00 report](../roadmap/audits/spike-00-platform-baseline.md). [ADR-003](../roadmap/decisions/ADR-003-simulator-mobile-foundation.md) adopts simulator acceptance for mobile development; runtime privacy coverage must be recorded by environment and is not inferred from a build. macOS is deferred.

## Required app behavior

- Games work offline. App code makes no network requests.
- Saves and settings stay on the device, separated by title. No accounts or cloud sync.
- No ads, in-app purchases, analytics, attribution, crash-reporting SDKs, remote configuration, push notifications or tracking-permission requests.
- No transport or persistent production collection of diagnostic counters. The experiment's in-memory HUD is a disposable testing aid.
- Privacy manifests and eventual store disclosures must describe the actual shipped bundle and behavior. Apple-operated distribution services sit outside the app contract and must not be confused with app data flows.

[ADR-005](../roadmap/decisions/ADR-005-local-save-durability.md) requires Epic 04 to exclude app-owned saves from OS backup and verify attributes after replacement. A deliberate player export creates a separate copy in the selected Files destination, which may use an external provider. The app does not sync or send that copy to the developer. Epic 04 implements these controls in the mobile practice. Its [evidence](../roadmap/audits/epic-04-local-state.md) records the simulator checks and their limits.

The first-party framework direction does not exempt a target from review. Entitlements, resources and indirect dependencies can change behavior even when no networking import appears in source.

## Change review checklist

Record the target/configuration, reviewer, evidence and unresolved items in the change description. Apply the relevant checks to both Debug and Release.

- Inspect added imports, package products, linked frameworks, scripts and bundled resources. Identify runtime services and all direct/transitive dependencies; development-only tools must be distinguished from shipped code.
- Compare capabilities and entitlements. Explain each addition and check for networking, cloud containers, push, tracking, commerce or service integration. A networking entitlement's absence is not proof of no network requests on every platform.
- Inspect generated and committed Info.plist values, permission strings, URL schemes, background modes and privacy manifests. Explain each permission/API declaration using actual behavior; do not add speculative declarations.
- Trace any data through creation, storage, access and deletion. Verify title namespaces and local-only paths when persistence is implemented. Identify any transport, identifiers, logging or telemetry introduced by the change.
- Inspect the built app and embedded bundles, including resolved packages and required notices. Confirm excluded upstream services/resources are absent. Keep the [inclusion inventory](../roadmap/audits/preflight-inclusion-bom.md) current.
- Run the relevant source/build checks and exercise the changed path offline in the supported mobile simulators or other available test environment. Record permission prompts and observed network activity with the observation method, run duration and coverage. Investigate unexpected traffic; a short quiet run is not proof of all-path compliance.

The experiment's `privacy-scan.sh` searches a limited list of APIs. Passing it is supporting evidence only. Release privacy and accessibility validation belongs to the later mobile release baseline and does not disappear when Epic 01 establishes these rules. No physical device is required for foundation development; simulator observations must not be described as physical-device certification.

## Before adding a dependency

Document the concrete requirement and why existing first-party APIs or original code do not meet it. Record the upstream URL, pinned revision/version, selected products and exact local paths; resolved transitive graph; licenses and notices for code and resources; maintenance owner and update plan; supported toolchain/platforms; reproducible build process; and runtime data flows/capabilities. Review all of these before inclusion.

Preflight approved no third-party material for inclusion. A design reference is not dependency approval. A dependency that requires behavior forbidden above needs an explicit product-contract decision; a favorable license review alone cannot authorize it.
