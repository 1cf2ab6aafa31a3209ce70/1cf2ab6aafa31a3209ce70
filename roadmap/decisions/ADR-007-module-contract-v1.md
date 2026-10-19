# ADR-007 — Module contract version 1

**Date:** 2026-10-19. **Status:** Accepted for Epic 07; provisional until [Spike 11](../spikes/11-dig-feasibility.md) confirms that a terrain title fits it.

## Context

[ADR-006](ADR-006-game-module-seam.md) accepted a compile-time registration seam inside the disposable [module-seam experiment](../../experiments/module-seam/README.md): a `GameModule` protocol with associated session and view types, a `ModuleSession` protocol and a generic `ModuleHost` that adapts them to `ShellController`'s closures. [Epic 07](../epics/07-module-integration.md) turns that seam into the production contract that every title target registers through, with title metadata, level decoding, a rules factory, gameplay view factories and lifecycle callbacks.

The development practice title predates the seam. It wired its scene straight into `ShellController` closures, so it could not show that a second title registers the same way.

## Decision

`GamePlatform` exports the contract:

- `GameModule`: an `@MainActor` class protocol with associated `Session: ModuleSession`, `Gameplay: View` and `Controls: View` types.
- `ModuleSession`: the retained, title-owned play session.
- `ModulePlayContext`: what the shell lends to play controls, namely the reduced-motion state and a pause action.
- `ModuleHost<Module>`: registers one module with a `ShellController`.
- `ModuleShellView<Module>`: the shared iOS shell around the module's views.

The epic's responsibilities map onto the contract as follows:

| Responsibility | Contract member |
| --- | --- |
| Title metadata | `title` (stable ID, display name, languages; the ID names the save namespace), `presentation`, `loadFailureMessage`, `contractVersion` |
| Level decoding | `ModuleSession.prepare(for:)` decodes and validates the selected level from the title's bundled content |
| Rules factory | `ModuleSession.begin(for:)` creates fresh rule state for the prepared request |
| Gameplay view factories | `makeGameplay()` and `makeControls(_:)` |
| Lifecycle callbacks | `playing`, `settings`, `setReducedMotion(_:)`, `outcomeHandler`, `fail()`, `recordSuccess(in:)` |

The promotion keeps ADR-006's demonstrated behavior: preparation is refused for an unsupported registration version before the session is touched, the bridge never dereferences the controller before initialization, settings arrive once at registration and again only when they change, and every outcome carries the request it belongs to, so the controller refuses late or duplicate results. A session must check cancellation before replacing staged state (ADR-006's S06-10).

Three things change from the experiment:

- **Identity and copy come from the module.** The experiment hard-coded the `development-practice` title ID and shell copy in its host. A module now supplies its `TitleRegistration`, `ShellPresentation` and load-failure message.
- **Play controls are title-owned.** The experiment's host added fixed Pause and End buttons around the module's controls. A module now lays out all of its play controls and receives `ModulePlayContext` for pause and reduced motion; it ends a session only through its own session, so outcomes stay request-bound.
- **The controller builds on the package's macOS test host.** `ShellController` and `ModuleHost` no longer sit behind `#if os(iOS)`, so the contract tests run with `swift test` on every change. The applications remain iOS-only, and `SharedShellView` and `ModuleShellView` stay iOS-only.

The development practice now registers through the contract: `PracticeModule` owns the SpriteKit scene, `PracticeSession` validates the bundled catalog in `prepare(for:)` and records its synthetic progress, and `ShellModel` remains the composition root that opens storage and DEBUG diagnostics. Its controls, copy, identifiers and save namespace are unchanged.

The version rule is ADR-006's. `contractVersion` is a source-integration version, separate from content and save schema versions. `ModuleHost.supportedContractVersions` is `1...1`; any other version fails loading with the module's message, and the host never treats it as version 1. A later version needs a named adapter with tests, or a separately versioned host that registrations opt into.

## Alternatives

Keeping the closure registration for the practice title and using the contract only for new titles would leave two registration paths and no evidence that the contract carries an existing title unchanged. Splitting level decoding and rule creation into separate module factories with a host-held per-request session would change the demonstrated shape without evidence that a title needs it, and would make each renderer rebind to a new session on every load. A shared renderer, entity or physics abstraction remains rejected for the reasons in ADR-006.

## Evidence and limits

`ModuleContractTests` run a fake module through launch, level load, pause and resume, foreground return, reduced motion, a success result, the save, and a relaunch that restores progress and settings. They also check a recoverable load failure, refusal of an unsupported version before preparation, late and duplicate outcomes, settings delivery, refusal of another title's save namespace, and returning to the menu during loading. The practice title's existing app-hosted and UI tests pass unchanged through the contract. The [Epic 07 audit](../audits/epic-07-module-integration.md) records commands, toolchains and runtimes.

Version 1 is demonstrated by one synthetic title and fakes. The block reference slice is the first title with real rules on it, and Spike 11 decides whether a terrain title fits it without a version 2.
