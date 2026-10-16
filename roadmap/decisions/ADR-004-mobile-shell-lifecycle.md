# ADR-004 — Mobile shell lifecycle

**Date:** 2026-10-01. **Status:** Accepted for Epic 02.

## Context

The shared mobile shell needs predictable play, loading, pause and result transitions before persistence or title-specific game rules exist. Backgrounding, audio interruptions and delayed preparation must not leave the renderer accepting input or let an old load complete a newer session.

## Decision

`GameCore` owns renderer-independent title metadata, settings values and a value-type flow coordinator. Each preparation request has a unique identity; completion and failure apply only to the current request. Invalid transitions return failure without changing state. A title owns its preparation function, scene and game rules.

Application inactivity and audio interruption are independent pause reasons. Ending a system interruption clears its blocker but leaves an explicit user pause. Returning to the foreground does not resume play automatically. Resume may recover audio focus, then requires all system blockers to be clear. Loading that overlaps an interruption enters pause before it can accept input. Route disconnection and media-service reset also pause the current practice.

`GamePlatform` owns the reusable `ShellController` and generic `SharedShellView`. The controller takes title metadata, asynchronous preparation and small scene-lifecycle closures. The view takes title copy and title-provided gameplay host/controls. Neither shared type imports a title or a renderer. This is a shell composition seam, not the final game-module protocol.

The development title retains one SpriteKit scene and connects it to one shared controller/feedback subscription. It declares a single iPad window because its session belongs to that window. Shared SwiftUI supplies semantic menus, settings and results with a scrollable layout for landscape and large text; the title's decorative scene is hidden from accessibility. Reduce Motion removes the sample's breathing action without removing play controls.

`GamePlatform` owns first-party audio, haptics and interruption notifications. Ambient audio respects the silent switch and mixes with other audio. Unsupported haptics do nothing. Observation is idempotent; teardown stops playback and releases only the audio session this output activated. There is no background playback capability, permission request, network service or third-party SDK.

At the Epic 02 baseline, sound, music and haptic preferences applied immediately and reset when the app process ended. [ADR-005](ADR-005-local-save-durability.md) and Epic 04 subsequently make production preferences durable; storage-free injected shell fixtures retain the earlier session-only behavior. The practice supports English only. At that baseline durable settings and language/content selection were separate roadmap work; the shell does not invent a storage format or localization catalog.

## Consequences

Epic 02 supplies a real lifecycle practice, not a complete puzzle game. Its title registration is intentionally small; [Spike 06](../spikes/06-module-seam.md) still has to prove the eventual multi-renderer module contract. [Spike 03](../spikes/03-save-durability.md) chooses save and settings durability before Epic 04 adds storage. Multiwindow behavior can be added when each window has an independent session owner.

Simulator tests establish transitions and adapter contracts. They do not establish physical audio/haptic fidelity, performance or execution on iOS 18. [ADR-003](ADR-003-simulator-mobile-foundation.md) keeps these distinctions explicit without blocking mobile development.
