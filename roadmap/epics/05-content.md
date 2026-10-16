# Epic 05 — Bundled content and reproducible levels

**Outcome:** Titles ship validated, versioned levels inside the app; QA can reproduce a level from its content version and seed without observing players.

**Entry:** Epic 04 provides local progress; earlier shell and repository contracts are stable. **Next:** Spike 06. This epic depends on all earlier ordered work.

## Scope and tasks

1. Define a shared level envelope: stable ID, schema version, game type, content version, seed, title-specific payload, and optional localization keys. No remote config or downloaded content.
2. Build a loader with clear errors and per-title decoders/validators. Reject duplicate IDs, missing assets, invalid references, unsupported versions, and malformed rules before packaging.
3. Provide deterministic RNG and a gameplay clock/input boundary where rules need replay. Keep any input traces in developer test fixtures; production saves retain only necessary progress.
4. Add a command-line validation tool that runs in CI and produces human-readable failures. Define a safe content migration rule when an update changes level IDs or order.
5. Document a local playtest report format: title, build, level ID, content version, seed, device, observed issue. It is manually shared by testers, never uploaded by the app.

## Acceptance

- Clean build rejects invalid bundled levels and passes a sample level for each planned game type.
- Given identical level content, seed, and input fixture, pure rules produce the same outcome in repeat runs on supported platforms.
- Installed offline build can enumerate and load all its levels.
- An updated content bundle does not silently erase earned completion for unchanged stable level IDs.

**Outside this epic:** A remote level service, experiments on players, or full game content.

## Status — 2026-10-02

Complete for mobile simulator acceptance. The [evidence report](../audits/epic-05-bundled-content.md) and [source manifest](../audits/epic-05-bundled-content-evidence.json) retain 72 package tests, all three build configurations, clean invalid-build rejection, installed resource checks and 23 app/UI tests per geometry with shutdown/boot restore proofs. Local and hosted results identify their exact inputs separately. The [authoring guide](../../docs/bundled-content.md) defines stable-ID updates, deterministic fixtures and manual playtest reports.

These are four original sample payloads and reference outcomes, not complete games or solvability certification. Minimum-runtime and distribution checks remain explicit under [ADR-003](../decisions/ADR-003-simulator-mobile-foundation.md); physical devices and macOS applications are outside current scope. Spike 06’s entry gate is met; its two-developer-day comparison has not started.
