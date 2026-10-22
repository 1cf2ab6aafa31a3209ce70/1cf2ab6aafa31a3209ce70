# Accessibility record: Few Tiles

This record applies the [accessibility checklist](../../docs/accessibility-checklist.md) to Few Tiles, the tile title of Epic 09B ([ADR-011](../../roadmap/decisions/ADR-011-tile-match-rules.md)). It lists each result, every fix and every tracked action. The automated checks are in [TileAccessibilityUITests](../../Tests/TileTitleUITests/TileAccessibilityUITests.swift), [TileTitleUITests](../../Tests/TileTitleUITests/TileTitleUITests.swift) and [TileTitleModuleTests](../../Tests/TileTitleTests/TileTitleModuleTests.swift). The interactive steps that Blocky Marty's [record](../BlockTitle/ACCESSIBILITY.md#interactive-steps) ran from scripts, and the device steps, are [Polishing](../../roadmap/polishing.md) items P-8 and P-9.

## Environment

Recorded 2026-10-21 on `2d52b04` (Epic 09B branch, after the review fixes) through `scripts/test-mobile.sh --title TileTitle`, on host Mac14,6 (Apple M2 Max), macOS 27.2, Xcode 27.1 (`27A9275`), iOS Simulator 26.0 (`23A5287g`), new owned simulators with iPhone 12 and iPad (9th generation) geometry, Debug build, portrait. All 20 tests (9 app-hosted, 11 UI) passed on both geometries on the first attempt, with no XCTest retry and no app-originated network activity. The same suite passed twice earlier on `e8c8a3c`, before the review fixes. Every result here is a simulator observation.

## Play page

Above the board's tile buttons the play page shows the board's place ("Board 1 of 30"), one teaching line on each of the first three boards, the tiles left, the score and the tray in words ("Tray: 2 Leaf, Drop; 4 slots free"), then, once a move has been made, Undo. Below the board, the tray's seven slots repeat the same symbols; VoiceOver reads them as one element, "Tray", with the same words as its value. Each free tile is a button named by kind, row, column and layer ("Leaf, row 1, column 2, layer 1"); a tile on an odd layer sits between two rows and two columns and names both ("Sun, row 1 to 2, column 2 to 3, layer 2"). Its hint says whether it clears a triple and which tiles it frees. Covered tiles are drawn dimmed on the board and are not controls: no two free tiles share a row and column, because tiles that do overlap. A full tray keeps the play page: the notice "The tray is full. Undo a move, or end the board." appears above Undo, Undo becomes the prominent button, the tile buttons go away, and VoiceOver announces the notice.

## Results

| Checklist item | How it was checked | Result |
| --- | --- | --- |
| 1. Labels and traits | Audits on menu, settings, play, pause, success, failure and a full tray at default size and AX3; `testTileButtonsDescribeEveryFreeTileAndClearTheBoardWithoutTheBoard` asserts the board's and the tray's labels and values and every tile button's label | Pass on every Few Tiles page at both sizes on both geometries; the only findings were on the settings sheet, excused under S-2, S-3 and, on iPad, S-4 |
| 2. Focus order | The same test compares the play page's element positions | Pass: heading, place, teaching, counts, tray, tiles, Pause, End board; Undo joins between the tray and the tiles after a move |
| 3. Large text | Audits with `--shell-large-text` (AX3, without `.dynamicType`) | Pass; at accessibility sizes the tile buttons go to one full-width button a row, as Blocky Marty's do |
| 4. Color-independent cues | `testEveryKindHasADistinctSymbolAndName`; every kind has its own SF Symbol and name on the board, in the tray and on the buttons; contrast audit | Pass. The Grayscale filter is in the [hardware check](../../docs/hardware-check.md) |
| 5. Reduced motion | `testReducedMotionReachesTheSessionAndTheBoardRunsNoActions`; `testReducedMotionKeepsPlayPauseAndResultsReachable` | Pass. The board has no animation: it redraws in one step |
| 6. Audio and haptics | Few Tiles plays no sound or haptic of its own, only the shell's success, failure and selection cues | Pass; device output is in the hardware check |
| 7. Alternate input | `testTileButtonsDescribeEveryFreeTileAndClearTheBoardWithoutTheBoard` clears a board with the buttons only; `hitRegion` audit; touch and buttons share `TileTitleSession.select(_:)` | Pass. Full Keyboard Access is Polishing P-8 |

## Tracked actions

Few Tiles has no open title-owned action. The settings findings belong to the shared shell and are the same entries as in Blocky Marty's [tracked actions](../BlockTitle/ACCESSIBILITY.md#tracked-actions): the audit test excuses S-2 and S-3 (fixed or false positives there) and S-4 (open; Polishing P-3) on the settings page only, with the same wording. S-6 (Polishing P-4) applies to this title's settings sheet too.
