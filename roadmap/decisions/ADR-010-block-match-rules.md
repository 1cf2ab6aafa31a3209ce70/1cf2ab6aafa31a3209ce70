# ADR-010 — Block Match rules

**Date:** 2026-10-21. **Status:** Proposed. Epic 09A's first task records the complete title's rules before any shared genre code. This record extends the Epic 07 reference slice's rules; four choices marked **Owner decision** need the project owner's answer before the rules are accepted.

## Context

The reference slice ([BlockRules.swift](../../Games/BlockContent/Sources/BlockContent/BlockRules.swift), [content record](../../Games/BlockTitle/CONTENT.md)) clears a group of two or more orthogonally connected blocks of one kind, lets the blocks above fall, wins on an empty board and ends without progress when no group of two remains. Each clear of n blocks scores n × (n − 1). Two hand-made boards ship.

Constraints the complete title keeps:

- **Accessible input.** Every move is possible from a standard button that names its block by row, column and kind ([accessibility checklist](../../docs/accessibility-checklist.md) item 7), by touch on the board, and from a keyboard. There is no drag, timing or multi-finger input.
- **Determinism.** A level, its seed and an input fixture fix the outcome; animation never advances the rules ([ADR-007](ADR-007-module-contract-v1.md)).
- **No dead ends.** Every shipped level is clearable, and the validator proves it before the level ships.
- **Distinct from the tile title.** Epic 09B documents its own rules against these.
- **Saves.** `SaveProgress` already records completed levels, unlocks and a best score per level.

## Decision

1. **Board.** A rectangular grid from 3 × 3 to 8 × 8, with two to four block kinds per level. Each kind keeps its own color, white mark and name: Coral circle, Teal square, Gold triangle, Violet diamond.
2. **Move.** Selecting any block of a group of two or more orthogonally connected blocks of one kind clears the whole group. Blocks above each cleared cell fall straight down. A block with no matching neighbor cannot be cleared: selecting it changes nothing, and its button's hint says so.
3. **Columns stay put (Owner decision).** An emptied column stays empty; columns never shift sideways. Collapse games usually close empty columns, but then every block to the right changes column after a move, and a VoiceOver or keyboard player loses the map they built from the block names. With fixed columns a move changes only the rows of the blocks above the gap. Alternative: close empty columns to the left, which makes boards easier to clear and harder to follow by name.
4. **End states.** A level is cleared when the board is empty. It is stuck when blocks remain and no group of two does; the result page says so in text and offers Undo, Play again and Back to menu.
5. **Undo (Owner decision).** Unlimited undo within one play: each undo restores the board and score before the last move. It is on the play page and on the stuck result page. Undo is an input in the replay fixtures, so a recorded play still reproduces. Rationale: a mistaken tap, a switch or keyboard slip, or an exploratory move costs nothing, and there is no timer to protect. Alternative: no undo, with Try again only, which makes stuck boards a real failure.
6. **Scoring (Owner decision).** Keep n × (n − 1) per clear, so planning larger groups pays. The result page shows the score and the level's best; the best is saved per level, as `SaveProgress` already allows. Undo does not cost points. There are no stars, par scores or timers in 09A. Alternative: drop the score and show only moves.
7. **Progression.** About 30 curated levels in three chapters: 3 × 3 to 5 × 5 with two kinds, 5 × 5 to 7 × 7 with three, 6 × 6 to 8 × 8 with four. Play opens the first uncompleted level; a cleared level offers Next level. After the final level, Play opens the first level again, and every level stays replayable. A level list is shared shell work and stays out of 09A.
8. **Teaching.** The first three levels carry one line of instruction each on the play page (select a group, blocks fall, a single block stays). There is no modal tutorial.
9. **Level authoring.** Levels are written by hand or generated from a seed by reverse construction: start from an empty board and insert removable groups, so every generated board has a known clearing sequence. The validator replays that sequence and still runs the solver within its state limit; a board that neither proves clearable is rejected. Generation runs at authoring time only; the app ships fixed boards.

## Consequences

- `BlockGame` gains an undo stack and an undo action in `BlockAction`; replay fixtures and their tests cover undo.
- The shell's result page needs a third action for Undo on the stuck result, or the title supplies it; whichever path, the action must be a standard button.
- `BlockCatalog` validation adds the chapter size and kind ranges and the reverse-construction proof.
- The content record and release metadata need the title's original name (**Owner decision**: the working title Block Match is a placeholder).
