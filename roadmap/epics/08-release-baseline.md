# Epic 08 — Quality and release baseline

**Outcome:** Any title built on the core has a repeatable path to a reviewable offline release, including privacy, accessibility, performance, and licensing checks.

**Entry:** Epic 07 has two app targets and a stable module contract. **Next:** Epic 09. This epic depends on all earlier ordered work.

## Scope and tasks

1. Set device-specific budgets for startup, frame pacing, memory, and package size using the hardware established by spike 00; automate repeatable smoke measurements where practical.
2. Audit built app bundles, entitlements, Info.plist entries, linked SDKs, and privacy manifests. Verify the App Store privacy answers from actual behavior, including Apple-required API disclosures where applicable.
3. Add offline operation and network-observation checks to the release procedure, plus tests that catch accidental use of URL sessions, web views, ad/IAP packages, and tracking permission APIs in app targets.
4. Build an accessibility checklist and test the reference title: VoiceOver labels and focus, large text in menus, color-independent cues, reduced motion, audio/haptic controls, and a usable alternate input path for gameplay.
5. Add localization and asset-license validation, reproducible build instructions, release notes template, and a manual device test matrix. Include a local reset/export path in the privacy description.

## Acceptance

- A release candidate for the reference title passes documented automated and manual gates on supported devices.
- App-bundle audit finds no ad, analytics, attribution, IAP, account, cloud, or push integration and no app-originated network traffic during exercised flows.
- A reviewer can trace every packaged third-party asset to its license and attribution requirement.
- Accessibility findings have either a fix or an explicit, tracked title-specific action before that title ships.

**Outside this epic:** Store submission, external services, and title-specific content polish.
