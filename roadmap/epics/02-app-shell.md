# Epic 02 — Shared app shell

**Outcome:** Every title can enter a common splash/loading → play → pause → result flow and survive foreground/background and interruptions. The shell remains offline and contains no analytics or monetization hooks.

**Entry:** Epic 01 builds on the platform matrix from spike 00. **Next:** Spike 03. This epic depends on all earlier ordered work.

## Scope and tasks

1. Define a small title registration interface and a flow coordinator that owns state transitions, loading errors, pause/resume, restart, and level completion. Keep game rules in the title module.
2. Implement SwiftUI menus and result screens, safe-area and orientation behavior, and a gameplay host for the chosen renderer.
3. Add first-party audio and haptic adapters with no-op behavior where a device lacks a capability. Audio focus and interruption handling must pause or restore cleanly.
4. Provide local settings UI for sound, music, haptics, and language where supported; use temporary in-memory settings until Epic 04 supplies durable storage.
5. Define semantic UI labels, reduced-motion behavior, and large-text behavior for the shell from the start.

## Acceptance

- A sample scene reaches play, pause, resume, restart, success, and failure from UI and lifecycle events.
- Backgrounding or an audio interruption cannot leave input active behind a paused scene or duplicate scene subscriptions on return.
- The shell works without a network connection, account, permission prompt, or third-party SDK.
- UI tests cover the navigation paths; unit tests cover legal and illegal flow transitions.

**Outside this epic:** Saved progress, bundled level schema, and title-specific game rules.
