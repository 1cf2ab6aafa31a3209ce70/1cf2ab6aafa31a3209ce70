# ADR-011 — Few Tiles rules

**Date:** 2026-10-21. **Status:** Accepted; rule 7 (scoring) is proposed and awaits the owner's confirmation. Epic 09B's first task records the tile title's rules, and how they differ from Blocky Marty's, before any genre code. The project owner chose the tray triple-match mechanic, unlimited undo and the name Few Tiles.

## Context

The development fixture's tile sample pairs equal tokens on a 2 × 2 grid ([FixtureRules.swift](../../Games/DevelopmentContent/Sources/DevelopmentContent/FixtureRules.swift)); it proves loading and replay, not a game. Three mechanics were offered: tray triple-match, layered pair-match (Mahjong solitaire's free-tile rule) and swap match-3 with cascades. The owner chose the tray: it is what app stores call tile match, it has no randomness during play and a real fail state, and reverse construction can prove every level clearable.

Constraints from Blocky Marty ([ADR-010](ADR-010-block-match-rules.md)) that this title keeps:

- **Accessible input.** Every move is possible from a standard button that names its tile, by touch on the board, and from a keyboard. There is no drag, timing or multi-finger input.
- **Determinism.** A level, its seed and an input fixture fix the outcome; animation never advances the rules ([ADR-007](ADR-007-module-contract-v1.md)).
- **No dead ends.** Every shipped level is clearable, and the validator proves it by replaying the level's recorded clearing sequence.
- **Saves.** `SaveProgress` records completed levels, unlocks and a best score per level.
- **Polishing.** Art, audio, animation and store metadata go to [Polishing](../polishing.md); this record fixes rules, levels and play only.

## Decision

1. **Name.** The title is **Few Tiles**: title ID `tile-match`, target `TileTitle`, content package `TileContent`. The name is user-facing only.
2. **Board.** Tiles lie in one to four layers. Positions use half-cell steps: each tile covers a square two half cells wide, and tiles on odd layers sit half a cell right of and below those on even layers, so one tile can rest on up to four below it. A tile is **covered** while any tile on a higher layer overlaps its square, and **free** otherwise. Each level uses two to six kinds, each kind a multiple of three tiles. Every kind has its own name, color and symbol: Leaf (green), Drop (blue), Sun (orange), Moon (indigo), Star (yellow), Heart (pink).
3. **Move.** Selecting a free tile moves it from the board into the tray, next to the tiles of its kind already there, or at the end. When the tray holds three tiles of one kind, those three clear at once. A covered tile cannot be selected; selecting it changes nothing.
4. **Tray.** The tray has seven slots and is shown with the board. A tile in the tray stays there until its kind's third tile arrives or the move is undone.
5. **End states.** A level is cleared when the board and the tray are empty; the shell's success page shows the score and the level's best and offers Next board and Back to menu. While tiles remain and the tray has room there is always a move, because a top tile is always free, so the only way to run out of moves is a **full tray**: seven tiles and no three alike. A full tray is a state of the play page, as Blocky Marty's stuck board is: the page says "The tray is full", announces it to VoiceOver, and offers Undo and End board. End board ends the play as a failure; the failure page offers Try again and Back to menu and records nothing.
6. **Undo.** Unlimited undo within one play: each undo puts the last selected tile back on the board and restores the tray and score before that move, from a full tray too. Undo is an input in the replay fixtures. A cleared board is final.
7. **Scoring (proposed).** Each triple scores the number of empty tray slots once it clears, from 3 to 7. Taking a kind's three tiles together keeps the tray clear and scores 7; parking tiles while hunting for partners scores less. The score counts only when the board is cleared; only a cleared play can set the level's best, and an ended play records nothing. There is no bonus, star rating, par score or timer, undo costs nothing, and progress never depends on the score. ADR-010's [scoring review](ADR-010-block-match-rules.md#scoring-review) applies unchanged: a score is a low-risk extra that should rank clears without competing with clearing as the goal. This rule measures the skill this title adds, planning around a seven-slot tray, with the same tray the player watches.
8. **Progression.** Thirty curated levels in three chapters of ten. Chapter 1: one or two layers, two or three kinds, 6 to 18 tiles. Chapter 2: two or three layers, three or four kinds, 18 to 36 tiles. Chapter 3: three or four layers, five or six kinds, 36 to 54 tiles. Unlocks, Play, Next board and the wrap after the last level follow ADR-010 rule 8.
9. **Teaching.** The first three levels carry one line each on the play page: select a tile to move it to the tray, and three alike clear; a tile under another frees up once every tile on it is gone; seven tiles fill the tray, and Undo takes back a move. There is no modal tutorial.
10. **Level authoring.** Levels are written by hand or generated from a seed by reverse construction. The generator lays out the plan's tile positions, draws an order in which every tile is free when its turn comes, and assigns kinds along that order so that no more than a planned number of kinds, at most three, have tiles waiting in the tray at once; playing that order therefore never holds more than six tiles and clears the board. Each level file carries that order as its clearing sequence, and the validator replays it. Generation runs at authoring time from a plan file that fixes each level's layout, kinds, seed and difficulty band, measured as the share of 1,000 uniformly random plays that clear it. The app ships fixed boards.

## How the rules differ from Blocky Marty

| | Blocky Marty | Few Tiles |
| --- | --- | --- |
| A move | Clears a connected group of two or more in place | Moves one tile to the tray; three alike clear there |
| What limits moves | Adjacency: a block needs a same-kind neighbor | Covering: a tile needs nothing on top of it |
| After a move | Blocks above fall; columns stay put | Nothing moves; tiles beneath may become free |
| Running out | Stuck: no group of two left | Full tray: seven tiles, no three alike |
| Board shape | One layer, rectangular grid | Up to four overlapping layers |
| What scores | Group size, n × (n − 1) per clear | Tray room, 3 to 7 per triple |
| Planning skill | Order of clears to build large groups | Which tiles to free and when, to keep the tray clear |

The two titles share no rule code. Few Tiles' covering is an overlap test between layers, not grid adjacency, so Epic 09B's optional shared grid helper has nothing to hold, and none is extracted.

## Consequences

- A `TileContent` package holds the rules (`TileBoard`, `TileGame` with tray and undo history, `TileAction` with select and undo), the level schema with each level's chapter, layers and clearing sequence, catalog validation that replays every sequence, and an authoring-only generator in the validator target.
- The title registers through module contract version 1 unchanged, using ADR-010's `resultSummary` and `successRetryLabel` for the result page.
- The module keeps a full tray on its play page with Undo and End board, and posts a VoiceOver announcement when the tray fills.
- The accessible controls list every free tile as a button that names its kind and position and says which tiles it frees; covered tiles are drawn dimmed on the board and are not controls.
- Art, audio and animation beyond system symbols and colors, the store record and the hands-on accessibility steps are [Polishing](../polishing.md) items.
