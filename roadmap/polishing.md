# Polishing

**Decision (2026-10-21, project owner):** a title epic closes when its rules, level set and play page are in place and pass the automated release gates and both titles' tests on both simulator geometries. Original art, audio and animation, store metadata, hands-on and device accessibility steps, and open shell findings are listed here and done later, outside the title epics. No title is distributed before its items here are done and the [hardware check](../docs/hardware-check.md) passes ([ADR-009](decisions/ADR-009-release-scope-without-hardware.md)).

Each item keeps its detail in the record named; this list says what is left and where it came from.

| ID | Scope | What is left | From | Record |
| --- | --- | --- | --- | --- |
| P-1 | Blocky Marty | Full Keyboard Access pass over the play page's Undo, the stuck-board notice and End board on both geometries; the scripted keyboard steps predate them | Epic 09A | [Accessibility record](../Games/BlockTitle/ACCESSIBILITY.md#epic-09a-play-page) |
| P-2 | Blocky Marty | VoiceOver announcement when a board becomes stuck; needs speech, so it runs with the hardware check | Epic 09A | [Hardware check](../docs/hardware-check.md) |
| P-3 | Shell | S-4: one `elementDetection` report on the iPad settings sheet that the audit cannot resolve to an element | Epic 08 | [Accessibility record](../Games/BlockTitle/ACCESSIBILITY.md) |
| P-4 | Shell | S-6: on iPad geometry, Full Keyboard Access cannot reach Done on the settings sheet | Epic 08 | [Accessibility record](../Games/BlockTitle/ACCESSIBILITY.md) |
| P-5 | Blocky Marty | Original art, audio and animation (Epic 09A task 3); animation stays out of the rules | Epic 09A | [ADR-010](decisions/ADR-010-block-match-rules.md) |
| P-6 | Blocky Marty | Release metadata: store record, description, screenshots and icon ([release checklist](../docs/release-checklist.md) sections 1, 5 and 7) | Epic 09A | [Content record](../Games/BlockTitle/CONTENT.md) |
| P-7 | Blocky Marty | Revisit the [Leaves of Blocks preflight findings](audits/preflight-leaves.md) for interaction and release patterns (Epic 09A task 6) | Epic 09A | This list |
